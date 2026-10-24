import Foundation
import Security

/// Auth tokens never enter UserDefaults or the shared contract.
enum RefreshTokenStore {
    private static let service = "com.unicaes.HospitalUniversitario.auth"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: "refresh-token"]
    }
    static func read() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw HospitalError.message("No se pudo leer la sesión del llavero.")
        }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ token: String) throws {
        let values = [kSecValueData as String: Data(token.utf8)]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var request = query
            request[kSecValueData as String] = Data(token.utf8)
            request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(request as CFDictionary, nil) == errSecSuccess else {
                throw HospitalError.message("No se pudo guardar la sesión en el llavero.")
            }
        } else if status != errSecSuccess { throw HospitalError.message("No se pudo actualizar la sesión.") }
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}

struct AuthSession: Decodable {
    let access_token: String
    let refresh_token: String
    let expires_in: Double
}

struct AccessProfile: Decodable {
    let id: UUID
    let status: String
    let preferred_name: String?
}

struct HospitalAccess: Decodable {
    struct Role: Decodable { let code: String; let facility_id: UUID }
    let profile: AccessProfile?
    let roles: [Role]
    let patient_id: UUID?
    let staff_id: UUID?
    let aal: String?
}

struct ResourcePage<T: Decodable>: Decodable {
    let data: [T]
    let has_more: Bool
    let next_cursor: ResourceCursor?
}

struct ResourceCursor: Codable {
    let id: UUID
    let value: String?
    var dictionary: [String: Any] { ["id": id.uuidString, "value": value as Any? ?? NSNull()] }
}

struct BackendFailure: Error, LocalizedError {
    let status: Int
    var errorDescription: String? {
        switch status {
        case 400, 422: return "Credenciales o datos inválidos. Revisa el correo y la contraseña."
        case 401: return "La sesión no es válida. Inicia sesión de nuevo."
        case 403: return "Tu cuenta no tiene acceso a esta información o requiere verificación."
        case 429: return "Demasiados intentos. Espera antes de volver a intentarlo."
        default: return "No se pudo conectar con el hospital. Inténtalo de nuevo."
        }
    }
}

@MainActor
final class HospitalAPI {
    let core: SharedCore
    private var session: AuthSession?
    private var expiry = Date.distantPast
    private var refreshTask: Task<AuthSession, Error>?
    private var shiftWindow: String?
    private let transport: URLSession

    init(core: SharedCore) {
        self.core = core
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.timeoutIntervalForRequest = 25
        transport = URLSession(configuration: config)
    }

    private func request(_ path: String, body: Data = Data("{}".utf8), token: String? = nil, method: String = "POST") async throws -> Data {
        guard let url = URL(string: core.configuration.url.absoluteString + path) else {
            throw HospitalError.message("La URL del hospital no es válida.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = method == "GET" ? nil : body
        request.setValue(core.configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await transport.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else { throw BackendFailure(status: response.statusCode) }
        return data
    }

    private func accept(_ value: AuthSession) throws {
        try RefreshTokenStore.save(value.refresh_token)
        session = value
        expiry = Date().addingTimeInterval(value.expires_in - 60)
    }

    func signIn(email: String, password: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password])
        let data = try await request("/auth/v1/token?grant_type=password", body: body)
        let value = try JSONDecoder().decode(AuthSession.self, from: data)
        do { try accept(value) }
        catch {
            _ = try? await request("/auth/v1/logout?scope=local", body: Data("{}".utf8), token: value.access_token)
            throw error
        }
    }

    func token() async throws -> String {
        if let session, expiry > Date() { return session.access_token }
        if let refreshTask { return try await refreshTask.value.access_token }
        guard let refresh = try RefreshTokenStore.read() else { throw BackendFailure(status: 401) }
        let task = Task { @MainActor in
            let body = try JSONSerialization.data(withJSONObject: ["refresh_token": refresh])
            let data: Data
            do { data = try await self.request("/auth/v1/token?grant_type=refresh_token", body: body) }
            catch let failure as BackendFailure where [400, 401, 403].contains(failure.status) {
                throw BackendFailure(status: 401)
            }
            let value = try JSONDecoder().decode(AuthSession.self, from: data)
            try self.accept(value)
            return value
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value.access_token
    }

    func access() async throws -> (HospitalAccess, [String]) {
        let data = try await request("/rest/v1/rpc/my_access", body: Data("{}".utf8), token: token())
        return (try JSONDecoder().decode(HospitalAccess.self, from: data), try core.roles(data))
    }

    func rooms(cursor: ResourceCursor? = nil) async throws -> ResourcePage<Room> {
        try await read("rooms", cursor: cursor)
    }

    func shifts(owner: UUID, cursor: ResourceCursor? = nil) async throws -> ResourcePage<StaffShift> {
        try await read("staff_shifts", cursor: cursor, owner: owner)
    }

    func tickets(owner: UUID, cursor: ResourceCursor? = nil) async throws -> ResourcePage<QueueTicket> {
        try await read("queue_tickets", cursor: cursor, owner: owner)
    }

    func rpc<T: Decodable>(_ name: String, parameters: [String: Any] = [:]) async throws -> T {
        let allowed = ["my_profile", "my_activity_summary", "my_queue_status", "hospital_overview"]
        guard allowed.contains(name) else { throw HospitalError.message("Consulta no disponible.") }
        let body = try JSONSerialization.data(withJSONObject: parameters)
        let data = try await request("/rest/v1/rpc/" + name, body: body, token: token())
        return try JSONDecoder().decode(T.self, from: data)
    }


    // El backend registra una solicitud; no reserva automáticamente un cupo médico.
    struct AppointmentSpecialty: Decodable, Identifiable {
        let id: UUID
        let name: String
    }

    struct DirectoryPhysician: Decodable, Identifiable {
        let physician_id: UUID
        let physician_name: String
        let specialty_id: UUID
        var id: UUID { physician_id }
    }

    func appointmentSpecialties() async throws -> [AppointmentSpecialty] {
        let body = try JSONSerialization.data(withJSONObject: [
            "p_resource": "specialties", "p_limit": 100, "p_sort": "name"
        ])
        let response = try await request("/rest/v1/rpc/read_resource", body: body, token: token())
        return try JSONDecoder().decode(ResourcePage<AppointmentSpecialty>.self, from: response).data
    }

    func appointmentPhysicians(facility: UUID, specialty: UUID) async throws -> [DirectoryPhysician] {
        let body = try JSONSerialization.data(withJSONObject: [
            "p_facility": facility.uuidString, "p_specialty": specialty.uuidString
        ])
        let response = try await request("/rest/v1/rpc/physician_directory", body: body, token: token())
        return try JSONDecoder().decode([DirectoryPhysician].self, from: response)
    }

    func requestAppointment(patient: UUID, facility: UUID, specialty: UUID, date: Date, from: Date, to: Date, reason: String, requestKey: UUID) async throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/El_Salvador")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        formatter.dateFormat = "HH:mm:ss"
        let start = formatter.string(from: from)
        let end = formatter.string(from: to)
        let body = try JSONSerialization.data(withJSONObject: [
            "p_patient": patient.uuidString, "p_facility": facility.uuidString,
            "p_specialty": specialty.uuidString, "p_reason": reason,
            "p_date": day, "p_from": start, "p_to": end,
            "p_request_key": requestKey.uuidString
        ])
        _ = try await request("/rest/v1/rpc/request_appointment", body: body, token: token())
    }

    func factors() async throws -> [MFAFactor] {
        struct AuthUser: Decodable { let factors: [MFAFactor]? }
        let data = try await request("/auth/v1/user", token: token(), method: "GET")
        return try JSONDecoder().decode(AuthUser.self, from: data).factors ?? []
    }

    func verifyTOTP(factor: UUID, code: String) async throws {
        struct Challenge: Decodable { let id: UUID }
        guard code.count == 6, code.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw HospitalError.message("Introduce el código de seis dígitos de tu autenticador.")
        }
        let token = try await token()
        let base = "/auth/v1/factors/" + factor.uuidString
        let challengeData = try await request(base + "/challenge", token: token)
        let challenge = try JSONDecoder().decode(Challenge.self, from: challengeData)
        let body = try JSONSerialization.data(withJSONObject: ["challenge_id": challenge.id.uuidString, "code": code])
        let data = try await request(base + "/verify", body: body, token: token)
        try accept(JSONDecoder().decode(AuthSession.self, from: data))
    }

    private func read<T: Decodable>(_ resource: String, cursor: ResourceCursor?, owner: UUID? = nil) async throws -> ResourcePage<T> {
        if resource == "staff_shifts" && (cursor == nil || shiftWindow == nil) { shiftWindow = try core.weekWindow() }
        let body = try core.request(resource: resource, cursor: cursor?.dictionary, owner: owner, window: resource == "staff_shifts" ? shiftWindow : nil)
        let data = try await request("/rest/v1/rpc/read_resource", body: body, token: token())
        let page = try JSONDecoder().decode(ResourcePage<T>.self, from: data)
        if page.has_more && page.next_cursor == nil { throw HospitalError.message("El servidor devolvió una página incompleta.") }
        return page
    }

    /// Always discards local credentials, even when the server is unreachable.
    func signOut() async -> String? {
        var warning: String?
        do {
            let accessToken = try await token()
            _ = try await request("/auth/v1/logout?scope=local", body: Data("{}".utf8), token: accessToken)
        } catch { warning = "Se cerró la sesión en este dispositivo. No se pudo confirmar el cierre remoto." }
        clearLocal()
        return warning
    }

    func clearLocal() {
        session = nil
        expiry = .distantPast
        shiftWindow = nil
        RefreshTokenStore.clear()
    }
}
