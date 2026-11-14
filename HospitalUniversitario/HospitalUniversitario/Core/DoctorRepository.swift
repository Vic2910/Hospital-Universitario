import Foundation
import Supabase

@MainActor
protocol DoctorRepositoryProtocol {
    func labCatalog() async throws -> [DoctorLabTest]
    func labOrders(offset: Int) async throws -> DoctorPatientLabPage
    func issueLabs(_ input: DoctorLabSelection) async throws
    func admissions(offset: Int) async throws -> DoctorAdmissionsPage
    func requestAdmission(_ input: DoctorAdmissionInput) async throws
    func patients(query: String, offset: Int) async throws -> DoctorPatientDirectoryPage
    func patientLabs(patient: UUID, offset: Int) async throws -> DoctorPatientLabPage
    func workspace(facility: UUID, from: Date, to: Date) async throws -> DoctorWorkspace
    func chart(patient: UUID, from: Date?, to: Date?, query: String) async throws -> DoctorPatientChart
    func start(appointment: UUID, requestKey: UUID) async throws
    func save(encounter: UUID, note: UUID?, version: Int?, draft: DoctorConsultationDraft, diagnosis: UUID?, requestKey: UUID) async throws
    func diagnoses(query: String, byCode: Bool) async throws -> [DoctorDiagnosis]
    func close(encounter: UUID, note: UUID, noteVersion: Int, encounterVersion: Int) async throws
    func issueOrder(encounter: UUID, test: Int64, instructions: String, requestKey: UUID) async throws
    func prescribe(encounter: UUID, lines: [DoctorRxLine], requestKey: UUID) async throws
    func markRead(_ notification: DoctorNotification) async throws
}

@MainActor
final class DoctorRepository: DoctorRepositoryProtocol {
    private let api: HospitalAPI
    init(api: HospitalAPI) { self.api = api }
    func labCatalog() async throws -> [DoctorLabTest] { try await call("lab_catalog",[:]) }
    func labOrders(offset: Int) async throws -> DoctorPatientLabPage { try await call("lab_orders",["p_offset":.number(offset)]) }
    func issueLabs(_ input: DoctorLabSelection) async throws {
        try await perform("labs",["p_encounter":.string(input.encounter.uuidString),"p_tests":.array(input.tests.map { .number(Int($0)) }),
            "p_reason":.string(input.reason),"p_key":.string(input.key.uuidString)])
    }
    func admissions(offset: Int) async throws -> DoctorAdmissionsPage {
        try await call("admissions", ["p_offset":.number(offset)])
    }
    func requestAdmission(_ input: DoctorAdmissionInput) async throws {
        try await perform("admission_request", ["p_patient":.string(input.patient.uuidString), "p_kind":.string(input.category),
            "p_reason":.string(input.reason), "p_instructions":.string(input.observations), "p_priority":.string(input.priority),
            "p_encounter":input.encounter.map { .string($0.uuidString) } ?? .null, "p_key":.string(input.key.uuidString)])
    }
    func patients(query: String, offset: Int) async throws -> DoctorPatientDirectoryPage {
        try await call("patients", ["p_query":.string(query),"p_offset":.number(offset)])
    }
    func patientLabs(patient: UUID, offset: Int) async throws -> DoctorPatientLabPage {
        try await call("patient_labs", ["p_patient":.string(patient.uuidString),"p_offset":.number(offset)])
    }

    private func call<T: Decodable>(_ name: String, _ parameters: [String: DoctorJSON]) async throws -> T {
        let values = try JSONSerialization.jsonObject(with: JSONEncoder().encode(parameters)) as? [String: Any] ?? [:]
        return try await api.doctorRPC(name, parameters: values)
    }

    private func perform(_ name: String, _ parameters: [String: DoctorJSON]) async throws {
        let _: DoctorJSON = try await call(name,parameters)
    }

    func workspace(facility: UUID, from: Date, to: Date) async throws -> DoctorWorkspace {
        try await call("workspace", ["p_from": .string(DoctorDate.timestamp(from)), "p_to": .string(DoctorDate.timestamp(to))])
    }

    func chart(patient: UUID, from: Date?, to: Date?, query: String) async throws -> DoctorPatientChart {
        try await call("chart", ["p_patient": .string(patient.uuidString),
            "p_from": from.map { .string(DoctorDate.timestamp($0)) } ?? .null,
            "p_to": to.map { .string(DoctorDate.timestamp($0)) } ?? .null,
            "p_query": .string(query)])
    }

    func start(appointment: UUID, requestKey: UUID) async throws {
        try await perform("start", ["p_appointment": .string(appointment.uuidString), "p_key": .string(requestKey.uuidString)])
    }

    func save(encounter: UUID, note: UUID?, version: Int?, draft: DoctorConsultationDraft, diagnosis: UUID?, requestKey: UUID) async throws {
        try await perform("save", ["p_encounter": .string(encounter.uuidString), "p_values": .object(draft.values),
            "p_version": .number(version ?? 0), "p_key": .string(requestKey.uuidString)])
    }

    func diagnoses(query: String, byCode: Bool) async throws -> [DoctorDiagnosis] {
        throw HospitalError.message("El catálogo de diagnósticos todavía no está adaptado a Hospital Móviles.")
    }

    func close(encounter: UUID, note: UUID, noteVersion: Int, encounterVersion: Int) async throws {
        try await perform("finish", ["p_encounter": .string(encounter.uuidString), "p_version": .number(encounterVersion)])
    }

    func issueOrder(encounter: UUID, test: Int64, instructions: String, requestKey: UUID) async throws {
        try await perform("lab", ["p_encounter": .string(encounter.uuidString),
            "p_test": .number(Int(test)), "p_reason": .string(instructions), "p_key": .string(requestKey.uuidString)])
    }
    func prescribe(encounter: UUID, lines: [DoctorRxLine], requestKey: UUID) async throws {
        try await perform("prescribe",["p_encounter":.string(encounter.uuidString),"p_key":.string(requestKey.uuidString),
            "p_lines":.array(lines.map(\.values))])
    }

    func markRead(_ notification: DoctorNotification) async throws {
        try await api.perform("updateItem", parameters: ["p_resource": .string("notifications"),
            "p_id": .string(notification.id.uuidString),
            "p_values": .object(["read_at": .string(DoctorDate.timestamp(Date()))]),
            "p_expected_version": .number(notification.row_version)])
    }
}
