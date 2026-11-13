import Foundation
import Supabase

@MainActor
final class MobileModuleRepository {
    private let api: HospitalAPI
    init(api: HospitalAPI) { self.api = api }
    func load(role: String, module: String, facility: UUID, from: Date?, to: Date?, query: String, cursor: ResourceCursor?) async throws -> MobileModulePage {
        try await api.operation("module", parameters: ["p_role": role, "p_module": module, "p_query": query,
            "p_from": from.map { DoctorDate.timestamp($0) } as Any? ?? NSNull(),
            "p_to": to.map { DoctorDate.timestamp($0) } as Any? ?? NSNull(),
            "p_cursor": cursor?.dictionary as Any? ?? NSNull()])
    }
    func perform(_ name: String, _ parameters: [String: DoctorJSON]) async throws { try await api.perform(name, parameters: parameters) }

    func changePassword(_ password: String) async throws {
        _ = try await api.client.auth.update(user: .init(password: password))
    }

    func documentURL(_ id: UUID) async throws -> URL {
        throw HospitalError.message("Los documentos todavía no están habilitados en Hospital Móviles.")
    }
}
