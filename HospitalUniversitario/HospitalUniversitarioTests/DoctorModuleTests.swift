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
    var labInputs: [DoctorLabSelection] = []
    var failLabs = false
    func labCatalog() async throws -> [DoctorLabTest] { [DoctorLabTest(id:1,code:"LOCAL",name:"Examen local",category:"Sangre"),DoctorLabTest(id:2,code:"LOCAL-2",name:"Segundo examen local",category:"Orina")] }
    func labOrders(offset: Int) async throws -> DoctorPatientLabPage { DoctorPatientLabPage(items:[],total:0,has_more:false,next_offset:nil) }
    func issueLabs(_ input:DoctorLabSelection) async throws { labInputs.append(input); if failLabs { throw URLError(.networkConnectionLost) } }
    var admissionInputs: [DoctorAdmissionInput] = []
    var failAdmission = false
    func admissions(offset: Int) async throws -> DoctorAdmissionsPage {
        DoctorAdmissionsPage(items:[],total:0,has_more:false,next_offset:nil,doctor_name:"Doctor de prueba",categories:["vip","semiprivada"],priorities:["normal","urgente"])
    }
    func requestAdmission(_ input: DoctorAdmissionInput) async throws {
        admissionInputs.append(input)
        if failAdmission { throw URLError(.networkConnectionLost) }
    }
    func patients(query: String, offset: Int) async throws -> DoctorPatientDirectoryPage {
        DoctorPatientDirectoryPage(patients:[DoctorAssignedPatient(id:patientID,full_name:"Paciente ficticio",record_number:"TEST",dui:"01234567-8",email:"paciente@example.test",phone:nil,birth_date:nil,age:nil,active_encounter_id:encounterID)],total:1,has_more:false,next_offset:nil)
    }
    func patientLabs(patient: UUID, offset: Int) async throws -> DoctorPatientLabPage {
        DoctorPatientLabPage(items:[],total:0,has_more:false,next_offset:nil)
    }

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
    func issueOrder(encounter: UUID, test: Int64, instructions: String, requestKey: UUID) async throws { }
    func prescribe(encounter: UUID, lines: [DoctorRxLine], requestKey: UUID) async throws { }
    func markRead(_ notification: DoctorNotification) async throws { }
}

struct DoctorModuleTests {
    @Test @MainActor func patientDirectoryDoesNotDependOnAppointmentsDay() async {
        let repository=DoctorRepositoryStub()
        let model=DoctorViewModel(repository:repository)
        model.configure(facility:UUID(),identity:UUID())
        model.day=Date(timeIntervalSince1970:0)
        await model.loadPatients()
        #expect(model.patientDirectory.count == 1)
        if let patient=model.patientDirectory.first {
            model.openPatient(patient)
            await model.loadChart()
            #expect(model.chart?.patient.id == patient.id)
            #expect(model.selectedPatient?.email == "paciente@example.test")
        }
        model.clear()
        #expect(model.patientDirectory.isEmpty && model.selectedPatient == nil && model.patientLabs.isEmpty)
    }
    @Test @MainActor func admissionRetryKeepsPatientAndKeyWithoutClinicalWrites() async {
        let repository=DoctorRepositoryStub()
        let admissionModel=DoctorViewModel(repository:repository)
        admissionModel.configure(facility:UUID(),identity:UUID())
        await admissionModel.loadAdmissions(); await admissionModel.loadPatients()
        if let patient=admissionModel.patientDirectory.first { admissionModel.openPatient(patient) }
        admissionModel.admissionCategory="vip"; admissionModel.admissionPriority="urgente"
        admissionModel.admissionReason="Motivo de ingreso local"; admissionModel.admissionForm=true
        repository.failAdmission=true
        await admissionModel.requestAdmission()
        #expect(admissionModel.pendingAdmission != nil)
        repository.failAdmission=false
        await admissionModel.requestAdmission()
        #expect(repository.admissionInputs.count == 2)
        #expect(repository.admissionInputs.first?.key == repository.admissionInputs.last?.key)
        #expect(repository.admissionInputs.first?.patient == repository.patientID)
        #expect(admissionModel.pendingAdmission == nil && !admissionModel.admissionForm)
        admissionModel.clear()
        #expect(admissionModel.admissions.isEmpty && admissionModel.admissionsPage == nil)
    }
    @Test @MainActor func multipleLabsRetryUsesTheSameSelectionAndKey() async {
        let repository=DoctorRepositoryStub()
        let labs=DoctorViewModel(repository:repository)
        labs.configure(facility:UUID(),identity:UUID()); await labs.refresh(); labs.select(repository.appointmentID)
        await labs.loadChart(); await labs.loadLabCatalog()
        labs.selectedLabIDs=[1,2]; labs.instructions="Indicaciones locales"
        repository.failLabs=true; await labs.issueSelectedLabs()
        #expect(labs.pendingLabs != nil)
        repository.failLabs=false; await labs.issueSelectedLabs()
        #expect(repository.labInputs.count == 2)
        #expect(repository.labInputs[0].key == repository.labInputs[1].key)
        #expect(repository.labInputs[0].tests == [1,2])
        #expect(labs.pendingLabs == nil && labs.selectedLabIDs.isEmpty)
        labs.clear(); #expect(labs.labCatalog.isEmpty && labs.ownLabOrders.isEmpty)
    }
    @Test func labCatalogUsesRealNumericIdentifiers() throws {
        let data = Data(#"{"id":15,"code":"15","name":"Catálogo de prueba"}"#.utf8)
        #expect(try JSONDecoder().decode(DoctorLabTest.self, from: data).id == 15)
    }
    @Test func incompleteClinicalDraftCanSaveButCannotFinalize() {
        let draft=DoctorConsultationDraft(subjective:"Motivo en revisión")
        #expect(draft.canSave)
        #expect(!draft.isValid)
    }
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
