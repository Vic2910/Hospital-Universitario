import Foundation
import Security
import Supabase

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
    static func clear() { SecItemDelete(query as CFDictionary) }
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

/// Datos de identidad que el paciente envía al registrar su cuenta.
///
/// Coinciden con los parámetros de `public.submit_patient_registration`. El
/// DUI usa el formato salvadoreño `00000000-0`; el teléfono, `0000-0000`.
struct RegistrationDraft {
    let facility: UUID
    let given: String
    let family: String
    let birthDate: String   // yyyy-MM-dd
    let sex: String         // female | male | intersex | unknown
    let dui: String         // 00000000-0
    let phone: String       // 0000-0000

    /// Única sede activa del hospital (hospital.facilities, código CENTRAL).
    static let centralFacility = UUID(uuidString: "3D101C8A-8974-4E2C-9144-1E777F632589")!
}

@MainActor
final class HospitalAPI {
    let core: SharedCore
    let client: SupabaseClient
    private var shiftWindow: String?
    private let transport: URLSession

    init(core: SharedCore) {
        self.core = core
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.timeoutIntervalForRequest = 25
        let transport = URLSession(configuration: config)
        self.transport = transport
        client = SupabaseClient(supabaseURL: core.configuration.url,
            supabaseKey: core.configuration.publishableKey,
            options: .init(auth: .init(storageKey: "hospital-universitario-session"),
                global: .init(session: transport)))
    }

    var hasStoredSession: Bool {
        client.auth.currentSession != nil || (try? RefreshTokenStore.read()) != nil
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

    func signIn(email: String, password: String) async throws {
        _ = try await client.auth.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        RefreshTokenStore.clear()
    }

    /// Crea la cuenta de autenticación del paciente. Devuelve `true` si el
    /// signUp ya entregó una sesión usable (confirmación de correo desactivada
    /// en el proyecto); `false` si el servidor no devolvió sesión y habrá que
    /// iniciar sesión antes de enviar la solicitud de registro.
    @discardableResult
    func signUp(email: String, password: String) async throws -> Bool {
        _ = try await client.auth.signUp(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        RefreshTokenStore.clear()
        return (try? await client.auth.session) != nil
    }

    /// Envía la solicitud de registro (con DUI y teléfono) a la base de datos
    /// mediante `public.submit_patient_registration`. Requiere una sesión
    /// autenticada con el correo confirmado y un perfil todavía `pending`.
    func submitPatientRegistration(_ draft: RegistrationDraft) async throws {
        let parameters: [String: Any] = [
            "p_facility": draft.facility.uuidString,
            "p_given_names": draft.given,
            "p_family_names": draft.family,
            "p_birth_date": draft.birthDate,
            "p_sex": draft.sex,
            "p_dui": draft.dui,
            "p_phone": draft.phone
        ]
        let body = try JSONSerialization.data(withJSONObject: parameters)
        _ = try await request("/rest/v1/rpc/submit_patient_registration", body: body, token: token())
    }

    func token() async throws -> String {
        if client.auth.currentSession == nil, let refresh = try RefreshTokenStore.read() {
            _ = try await client.auth.refreshSession(refreshToken: refresh)
            RefreshTokenStore.clear()
        }
        return try await client.auth.session.accessToken
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
            try await client.auth.signOut(scope: .local)
        } catch { warning = "Se cerró la sesión en este dispositivo. No se pudo confirmar el cierre remoto." }
        RefreshTokenStore.clear()
        shiftWindow = nil
        return warning
    }

    func clearLocal() async {
        try? await client.auth.signOut(scope: .local)
        shiftWindow = nil
        RefreshTokenStore.clear()
    }
}
