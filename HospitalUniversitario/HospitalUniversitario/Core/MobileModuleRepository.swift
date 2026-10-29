import Foundation
import Supabase

@MainActor
final class MobileModuleRepository {
    private let client: SupabaseClient
    private let projectURL: URL
    init(client: SupabaseClient, projectURL: URL) { self.client = client; self.projectURL = projectURL }

    func load(role: String, module: String, facility: UUID, from: Date?, to: Date?, query: String, cursor: ResourceCursor?) async throws -> MobileModulePage {
        let parameters: [String: DoctorJSON] = ["p_role": .string(role), "p_module": .string(module),
            "p_facility": .string(facility.uuidString), "p_query": .string(query), "p_limit": .number(25),
            "p_from": from.map { .string(DoctorDate.timestamp($0)) } ?? .null,
            "p_to": to.map { .string(DoctorDate.timestamp($0)) } ?? .null,
            "p_cursor": cursor.map { .object(["id": .string($0.id.uuidString), "value": $0.value.map { .string($0) } ?? .null]) } ?? .null]
        let response = try await client.rpc("mobile_module", params: parameters).execute()
        let page = try JSONDecoder().decode(MobileModulePage.self, from: response.data)
        guard !page.has_more || page.next_cursor != nil else { throw HospitalError.message("Paginación incompleta.") }
        return page
    }

    func perform(_ name: String, _ parameters: [String: DoctorJSON]) async throws {
        let allowed = ["request_appointment", "transition_appointment", "update_record", "create_record", "update_my_phone", "set_my_emergency_contact", "mobile_issue_prescription", "confirm_shift"]
        guard allowed.contains(name) else { throw HospitalError.message("Operación no autorizada.") }
        _ = try await client.rpc(name, params: parameters).execute()
    }

    func changePassword(_ password: String) async throws {
        _ = try await client.auth.update(user: .init(password: password))
    }

    func documentURL(_ id: UUID) async throws -> URL {
        struct Document: Decodable { let url: URL }
        let value: Document = try await client.functions.invoke("document-access", options: .init(body: ["document_id": id.uuidString]))
        guard value.url.scheme == "https", value.url.host == projectURL.host,
              value.url.path.hasPrefix("/storage/v1/object/sign/hospital-files/") else {
            throw HospitalError.message("El documento no devolvió un enlace seguro.")
        }
        return value.url
    }
}
