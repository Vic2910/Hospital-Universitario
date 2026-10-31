import Foundation
import Testing
@testable import HospitalUniversitario

@MainActor
private final class DoctorRepositoryStub: DoctorRepositoryProtocol {
    let appointmentID = UUID()
    let patientID = UUID()
    var chartRequests = 0
    var saveKeys: [UUID] = []
    var failSave = false
    var requestedFrom: Date?
    var requestedTo: Date?
    var requestedQuery = ""
    private let encounterID = UUID()

    func workspace(facility: UUID, from: Date, to: Date) async throws -> DoctorWorkspace {
        DoctorWorkspace(doctor_name: "Doctor de prueba", facility_name: "Sede de prueba",
            appointments: [DoctorAppointment(id: appointmentID, patient_id: patientID, patient_name: "Paciente ficticio",
                record_number: "TEST", phone: nil, ticket_number: nil, period: "", status: "in_progress", encounter_id: encounterID)],
            orders: [], tests: [], notifications: [],
            stats: .init(consultations: 1, completed_consultations: 0, issued_orders: 0, pending_orders: 0))
    }
    func chart(patient: UUID, from: Date?, to: Date?, query: String) async throws -> DoctorPatientChart {
        chartRequests += 1; requestedFrom = from; requestedTo = to; requestedQuery = query
        return DoctorPatientChart(patient: .init(id: patientID, full_name: "Paciente ficticio", record_number: "TEST",
            birth_date: nil, sex: nil, phone: nil, email: nil, address: nil, identification: nil),
            allergies: [], conditions: [], history: [DoctorConsultation(id: encounterID, started_at: "2026-10-28T12:00:00Z",
                status: "open", subjective: "Motivo", objective: "Exploracion", assessment: "Evaluacion",
                plan: "Plan", note_id: nil, note_version: nil, row_version: 1)])
    }
    func start(appointment: UUID, requestKey: UUID) async throws { }
    func diagnoses(query: String, byCode: Bool) async throws -> [DoctorDiagnosis] { [] }
    func save(encounter: UUID, note: UUID?, version: Int?, draft: DoctorConsultationDraft, diagnosis: UUID?, requestKey: UUID) async throws {
        saveKeys.append(requestKey)
        if failSave { throw URLError(.networkConnectionLost) }
    }
    func close(encounter: UUID, note: UUID, noteVersion: Int, encounterVersion: Int) async throws { }
    func issueOrder(encounter: UUID, test: UUID, instructions: String, weight: Decimal, height: Decimal, requestKey: UUID) async throws { }
    func markRead(_ notification: DoctorNotification) async throws { }
}

struct DoctorModuleTests {
    @Test func timestampsAcceptPostgresPrecision() {
        #expect(DoctorDate.parse("2026-10-28T12:00:00.123456+00:00") != nil)
        #expect(DoctorDate.parse("2026-10-28T12:00:00Z") != nil)
        #expect(DoctorDate.parse("not-a-date") == nil)
    }

    @Test func consultationRejectsWhitespaceAndOversizedNotes() {
        var draft = DoctorConsultationDraft(subjective: " ", objective: "Exploracion", assessment: "Evaluacion", plan: "Plan")
        #expect(!draft.isValid)
        draft.subjective = "Motivo"
        #expect(draft.isValid)
        draft.plan = String(repeating: "a", count: 10001)
        #expect(!draft.isValid)
    }

    @Test @MainActor func logoutClearsClinicalStateAndDrafts() async {
        let repository = DoctorRepositoryStub()
        let model = DoctorViewModel(repository: repository)
        model.configure(facility: UUID(), identity: UUID())
        await model.refresh()
        model.select(repository.appointmentID)
        await model.loadChart()
        #expect(model.contextChart != nil)
        model.instructions = "Indicaciones de prueba"
        model.clear()
        #expect(model.workspace == nil)
        #expect(model.chart == nil)
        #expect(model.contextChart == nil)
        #expect(model.selectedAppointmentID == nil)
        #expect(model.draft == DoctorConsultationDraft())
        #expect(model.instructions.isEmpty)
    }

    @Test @MainActor func historyRejectsReversedRangeAndPreservesTimeFilters() async {
        let repository = DoctorRepositoryStub()
        let model = DoctorViewModel(repository: repository)
        model.configure(facility: UUID(), identity: UUID())
        await model.refresh(); model.select(repository.appointmentID)
        model.filterDates = true
        model.historyFrom = Date(timeIntervalSince1970: 200)
        model.historyTo = Date(timeIntervalSince1970: 100)
        await model.loadChart(filtered: true)
        #expect(repository.chartRequests == 0)
        #expect(model.error != nil)
        model.historyTo = Date(timeIntervalSince1970: 300)
        model.historyQuery = "  seguimiento  "
        await model.loadChart(filtered: true)
        #expect(repository.requestedFrom == Date(timeIntervalSince1970: 200))
        #expect(repository.requestedTo == Date(timeIntervalSince1970: 300))
        #expect(repository.requestedQuery == "seguimiento")
    }

    @Test @MainActor func retryKeepsRequestKeyAfterAmbiguousNetworkFailure() async {
        let repository = DoctorRepositoryStub()
        let model = DoctorViewModel(repository: repository)
        model.configure(facility: UUID(), identity: UUID())
        await model.refresh(); model.select(repository.appointmentID); await model.loadChart()
        repository.failSave = true
        await model.saveConsultation(); await model.saveConsultation()
        #expect(repository.saveKeys.count == 2)
        #expect(repository.saveKeys.first == repository.saveKeys.last)
        #expect(model.error != nil)
        #expect(!model.saving)
    }
}
