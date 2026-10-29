import Foundation
import Supabase

@MainActor
protocol DoctorRepositoryProtocol {
    func workspace(facility: UUID, from: Date, to: Date) async throws -> DoctorWorkspace
    func chart(patient: UUID, from: Date?, to: Date?, query: String) async throws -> DoctorPatientChart
    func start(appointment: UUID, requestKey: UUID) async throws
    func save(encounter: UUID, note: UUID?, version: Int?, draft: DoctorConsultationDraft, diagnosis: UUID?, requestKey: UUID) async throws
    func diagnoses(query: String, byCode: Bool) async throws -> [DoctorDiagnosis]
    func close(encounter: UUID, note: UUID, noteVersion: Int, encounterVersion: Int) async throws
    func issueOrder(encounter: UUID, test: UUID, instructions: String, requestKey: UUID) async throws
    func markRead(_ notification: DoctorNotification) async throws
}

@MainActor
final class DoctorRepository: DoctorRepositoryProtocol {
    private let client: SupabaseClient
    init(client: SupabaseClient) { self.client = client }

    private func call<T: Decodable>(_ name: String, _ parameters: [String: DoctorJSON]) async throws -> T {
        let response = try await client.rpc(name, params: parameters).execute()
        return try JSONDecoder().decode(T.self, from: response.data)
    }

    private func perform(_ name: String, _ parameters: [String: DoctorJSON]) async throws {
        _ = try await client.rpc(name, params: parameters).execute()
    }

    func workspace(facility: UUID, from: Date, to: Date) async throws -> DoctorWorkspace {
        try await call("doctor_workspace", ["p_facility": .string(facility.uuidString),
            "p_from": .string(DoctorDate.timestamp(from)), "p_to": .string(DoctorDate.timestamp(to))])
    }

    func chart(patient: UUID, from: Date?, to: Date?, query: String) async throws -> DoctorPatientChart {
        try await call("doctor_chart", ["p_patient": .string(patient.uuidString),
            "p_from": from.map { .string(DoctorDate.timestamp($0)) } ?? .null,
            "p_to": to.map { .string(DoctorDate.timestamp($0)) } ?? .null,
            "p_query": .string(query)])
    }

    func start(appointment: UUID, requestKey: UUID) async throws {
        try await perform("start_consultation", ["p_appointment": .string(appointment.uuidString),
            "p_request_key": .string(requestKey.uuidString)])
    }

    func save(encounter: UUID, note: UUID?, version: Int?, draft: DoctorConsultationDraft, diagnosis: UUID?, requestKey: UUID) async throws {
        try await perform("save_consultation", ["p_encounter": .string(encounter.uuidString),
            "p_note": note.map { .string($0.uuidString) } ?? .null,
            "p_values": .object(draft.values), "p_diagnosis": diagnosis.map { .string($0.uuidString) } ?? .null,
            "p_expected_version": version.map { .number($0) } ?? .null,
            "p_request_key": .string(requestKey.uuidString)])
    }

    func diagnoses(query: String, byCode: Bool) async throws -> [DoctorDiagnosis] {
        let result: ResourcePage<DoctorDiagnosis> = try await call("read_resource", ["p_resource": .string("diagnosis_codes"),
            "p_filters": .array([.object(["column": .string(byCode ? "code" : "description"), "op": .string("ilike"), "value": .string("%" + query + "%")])]),
            "p_limit": .number(25), "p_sort": .string("code"), "p_direction": .string("asc"), "p_cursor": .null])
        return result.data
    }

    func close(encounter: UUID, note: UUID, noteVersion: Int, encounterVersion: Int) async throws {
        try await perform("close_consultation", ["p_encounter": .string(encounter.uuidString),
            "p_note": .string(note.uuidString), "p_note_version": .number(noteVersion),
            "p_expected_version": .number(encounterVersion)])
    }

    func issueOrder(encounter: UUID, test: UUID, instructions: String, requestKey: UUID) async throws {
        try await perform("doctor_issue_lab_order", ["p_encounter": .string(encounter.uuidString),
            "p_test": .string(test.uuidString), "p_instructions": .string(instructions),
            "p_request_key": .string(requestKey.uuidString)])
    }

    func markRead(_ notification: DoctorNotification) async throws {
        try await perform("update_record", ["p_resource": .string("notifications"),
            "p_id": .string(notification.id.uuidString),
            "p_values": .object(["read_at": .string(DoctorDate.timestamp(Date()))]),
            "p_expected_version": .number(notification.row_version)])
    }
}
