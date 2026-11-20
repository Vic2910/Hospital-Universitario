import Foundation
import Supabase

struct AccessProfile: Decodable {
    let id: UUID
    let status: String
    let preferred_name: String?
    let greeting_name: String?
}

struct HospitalAccess: Decodable {
    struct Role: Decodable { let code: String; let context_id: UUID }
    let profile: AccessProfile?
    let roles: [Role]
    let patient_id: UUID?
    let staff_id: UUID?
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
    let client: SupabaseClient
    private var context: [String: Any]?
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
            options: .init(auth: .init(storageKey: "hospital-moviles-uvebpsbbwofthucghccc"),
                global: .init(session: transport)))
    }

    var hasStoredSession: Bool { client.auth.currentSession != nil }
    private func request(_ path: String, body: Any? = nil, method: String = "GET") async throws -> Any {
        guard path.hasPrefix("/rest/v1/") || path == "/auth/v1/user",
              let url = URL(string: core.configuration.url.absoluteString + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if method != "GET", let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        request.setValue(core.configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else {
            if path.hasPrefix("/rest/v1/rpc/"), (path.contains("attention") || path.contains("doctor_native_")),
               let problem = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let code = problem["code"] as? String, ["22023", "42501", "40001"].contains(code),
               let message = problem["message"] as? String {
                if code == "40001" && path.contains("doctor_native_") { throw HospitalError.conflict(message) }
                throw HospitalError.message(message)
            }
            throw BackendFailure(status: response.statusCode)
        }
        if data.isEmpty { return NSNull() }
        return try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
    }

    func signIn(email: String, password: String) async throws {
        _ = try await client.auth.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        context = nil
    }

    func signUp(email: String, password: String, metadata: [String: String]) async throws -> Bool {
        let result = try await client.auth.signUp(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password, data: metadata.mapValues { .string($0) })
        context = nil
        return result.session != nil
    }

    func token() async throws -> String { try await client.auth.session.accessToken }
    func doctorRPC<T: Decodable>(_ name: String, parameters: [String: Any] = [:]) async throws -> T {
        guard ["workspace", "chart", "start", "save", "lab", "prescribe", "finish", "patients", "patient_labs", "admissions", "admission_request", "lab_catalog", "lab_orders", "labs", "alerts"].contains(name) else {
            throw HospitalError.message("Operación médica no permitida.")
        }
        let value = try await request("/rest/v1/rpc/doctor_native_" + name, body: parameters, method: "POST")
        let data = try JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)
        return try JSONDecoder().decode(T.self, from: data)
    }
    /// Lectura de una sola fila (RLS: admin, recepción o médico); sirve para saber si la agenda cambió sin pedirla entera.
    func planningRevision() async throws -> Int64? {
        let rows = try await request("/rest/v1/planning_revision?select=revision&limit=1") as? [[String: Any]]
        return (rows?.first?["revision"] as? NSNumber)?.int64Value
    }
    func attentionRPC<T: Decodable>(_ name: String, parameters: [String: Any] = [:]) async throws -> T {
        guard ["my_attention_context", "my_attention_requests", "submit_my_attention_request"].contains(name) else {
            throw HospitalError.message("Operación de atención no permitida.")
        }
        let value = try await request("/rest/v1/rpc/" + name, body: parameters, method: "POST")
        let data = try JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)
        return try JSONDecoder().decode(T.self, from: data)
    }
    func access() async throws -> (HospitalAccess, [String]) {
        guard let user = try await request("/auth/v1/user") as? [String: Any],
              let key = user["id"] as? String, UUID(uuidString: key) != nil else { throw URLError(.badServerResponse) }
        let profiles = try await request("/rest/v1/profiles?select=id,first_name,last_name,phone,birth_date,city&id=eq.\(key)") as? [[String: Any]] ?? []
        let roles = try await request("/rest/v1/user_roles?select=user_id,role,active&user_id=eq.\(key)")
        let patients = try await request("/rest/v1/patients?select=id,profile_id&profile_id=eq.\(key)")
        let staffRows = try await request("/rest/v1/staff?select=id,profile_id,active,category&profile_id=eq.\(key)") as? [[String: Any]] ?? []
        let staff = staffRows.filter { ($0["category"] as? String) == "doctor" }
        guard let profile = profiles.first,
              let value = try core.call("backendAccess", arguments: [user, profile, roles, patients, staff]).toDictionary() as? [String: Any] else { throw HospitalError.message("No se encontró tu perfil.") }
        context = value
        let data = try JSONSerialization.data(withJSONObject: value)
        return (try JSONDecoder().decode(HospitalAccess.self, from: data), try core.roles(data))
    }
    func operation<T: Decodable>(_ kind: String, parameters: [String: Any] = [:]) async throws -> T {
        if context == nil { _ = try await access() }
        guard let context,
              let plan = try core.call("backendPlan", arguments: [kind, parameters, context]).toArray() as? [[String: Any]] else { throw HospitalError.message("Operación no disponible.") }
        var results: [Any] = []
        for step in plan {
            guard let path = step["path"] as? String, let method = step["method"] as? String else { throw URLError(.badURL) }
            results.append(try await request(path, body: step["body"], method: method))
        }
        let result = try core.call("backendPresent", arguments: [kind, parameters, context, results])
        let data = try JSONSerialization.data(withJSONObject: result.toObject() ?? NSNull(), options: .fragmentsAllowed)
        return try JSONDecoder().decode(T.self, from: data)
    }
    func perform(_ kind: String, parameters: [String: DoctorJSON]) async throws {
        let values = try JSONSerialization.jsonObject(with: JSONEncoder().encode(parameters)) as? [String: Any] ?? [:]
        let _: DoctorJSON = try await operation(kind, parameters: values)
    }
    func rooms(cursor: ResourceCursor? = nil) async throws -> ResourcePage<Room> {
        try await operation("rooms", parameters: ["cursor": cursor?.dictionary as Any? ?? NSNull()])
    }
    func shifts(owner: UUID, cursor: ResourceCursor? = nil) async throws -> ResourcePage<StaffShift> {
        try await operation("shifts", parameters: ["cursor": cursor?.dictionary as Any? ?? NSNull(), "window": core.weekWindow()])
    }

    /// Always discards local credentials, even when the server is unreachable.
    func signOut() async -> String? {
        var warning: String?
        do {
            try await client.auth.signOut(scope: .local)
        } catch { warning = "Se cerró la sesión en este dispositivo. No se pudo confirmar el cierre remoto." }
        context = nil
        return warning
    }

    func clearLocal() async {
        try? await client.auth.signOut(scope: .local)
        context = nil
    }
}
