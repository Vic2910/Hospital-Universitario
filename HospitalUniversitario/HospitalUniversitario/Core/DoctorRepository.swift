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
    private let api: HospitalAPI
    init(api: HospitalAPI) { self.api = api }

    private func call<T: Decodable>(_ name: String, _ parameters: [String: DoctorJSON]) async throws -> T {
        let values = try JSONSerialization.jsonObject(with: JSONEncoder().encode(parameters)) as? [String: Any] ?? [:]
        return try await api.operation(name, parameters: values)
    }

    private func perform(_ name: String, _ parameters: [String: DoctorJSON]) async throws {
        try await api.perform(name, parameters: parameters)
    }

    func workspace(facility: UUID, from: Date, to: Date) async throws -> DoctorWorkspace {
        try await call("workspace", ["p_facility": .string(facility.uuidString),
            "p_from": .string(DoctorDate.timestamp(from)), "p_to": .string(DoctorDate.timestamp(to))])
    }

    func chart(patient: UUID, from: Date?, to: Date?, query: String) async throws -> DoctorPatientChart {
        try await call("patientChart", ["p_patient": .string(patient.uuidString),
            "p_from": from.map { .string(DoctorDate.timestamp($0)) } ?? .null,
            "p_to": to.map { .string(DoctorDate.timestamp($0)) } ?? .null,
            "p_query": .string(query)])
    }

    func start(appointment: UUID, requestKey: UUID) async throws {
        try await perform("startConsultation", ["p_appointment": .string(appointment.uuidString),
            "p_request_key": .string(requestKey.uuidString)])
    }

    func save(encounter: UUID, note: UUID?, version: Int?, draft: DoctorConsultationDraft, diagnosis: UUID?, requestKey: UUID) async throws {
        try await perform("saveConsultation", ["p_encounter": .string(encounter.uuidString),
            "p_note": note.map { .string($0.uuidString) } ?? .null,
            "p_values": .object(draft.values), "p_diagnosis": diagnosis.map { .string($0.uuidString) } ?? .null,
            "p_expected_version": version.map { .number($0) } ?? .null,
            "p_request_key": .string(requestKey.uuidString)])
    }

    func diagnoses(query: String, byCode: Bool) async throws -> [DoctorDiagnosis] {
        throw HospitalError.message("El catálogo de diagnósticos todavía no está adaptado a Hospital Móviles.")
    }

    func close(encounter: UUID, note: UUID, noteVersion: Int, encounterVersion: Int) async throws {
        try await perform("closeConsultation", ["p_encounter": .string(encounter.uuidString),
            "p_note": .string(note.uuidString), "p_note_version": .number(noteVersion),
            "p_expected_version": .number(encounterVersion)])
    }

    func issueOrder(encounter: UUID, test: UUID, instructions: String, requestKey: UUID) async throws {
        try await perform("issueLab", ["p_encounter": .string(encounter.uuidString),
            "p_test": .string(test.uuidString), "p_instructions": .string(instructions),
            "p_request_key": .string(requestKey.uuidString)])
    }

    func markRead(_ notification: DoctorNotification) async throws {
        try await perform("updateItem", ["p_resource": .string("notifications"),
            "p_id": .string(notification.id.uuidString),
            "p_values": .object(["read_at": .string(DoctorDate.timestamp(Date()))]),
            "p_expected_version": .number(notification.row_version)])
    }
}
