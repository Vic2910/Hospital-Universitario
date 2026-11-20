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
    var closeCalls = 0
    /// Versión guardada de la nota (doctor_native_save devuelve version+1); nil = nunca guardada.
    var noteVersion: Int?
    var conflictOnce = false
    var savedDrafts: [DoctorConsultationDraft] = []
    var appointments: [DoctorAppointment]?
    var history: [DoctorConsultation]?
    func alerts(offset: Int) async throws -> DoctorAlerts { DoctorAlerts(items: [], unread: 0, has_more: false, upcoming: []) }
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
    var patientQueries: [String] = []
    func patients(query: String, offset: Int) async throws -> DoctorPatientDirectoryPage {
        patientQueries.append(query)
        DoctorPatientDirectoryPage(patients:[DoctorAssignedPatient(id:patientID,full_name:"Paciente ficticio",record_number:"TEST",dui:"01234567-8",email:"paciente@example.test",phone:nil,birth_date:nil,age:nil,active_encounter_id:encounterID)],total:1,has_more:false,next_offset:nil)
    }
    func patientLabs(patient: UUID, offset: Int) async throws -> DoctorPatientLabPage {
        DoctorPatientLabPage(items:[],total:0,has_more:false,next_offset:nil)
    }

    func workspace(facility: UUID, from: Date, to: Date) async throws -> DoctorWorkspace {
        DoctorWorkspace(doctor_name: "Doctor de prueba", facility_name: "Sede de prueba",
            appointments: appointments ?? [DoctorAppointment(id: appointmentID, patient_id: patientID, patient_name: "Paciente ficticio",
                record_number: "TEST", phone: nil, ticket_number: nil, period: "", status: "in_progress", encounter_id: encounterID)],
            orders: [], tests: [], notifications: [],
            stats: .init(consultations: 1, completed_consultations: 0, issued_orders: 0, pending_orders: 0))
    }
    func chart(patient: UUID, from: Date?, to: Date?, query: String) async throws -> DoctorPatientChart {
        chartRequests += 1; requestedFrom = from; requestedTo = to; requestedQuery = query
        return DoctorPatientChart(patient: .init(id: patientID, full_name: "Paciente ficticio", record_number: "TEST",
            birth_date: nil, sex: nil, phone: nil, email: nil, address: nil, identification: nil),
            allergies: [], conditions: [], history: history ?? [DoctorConsultation(id: encounterID, started_at: "2026-10-28T12:00:00Z",
                status: "open", subjective: "Motivo", objective: "Exploracion", assessment: "Evaluacion",
                plan: notePlan, note_id: noteVersion == nil ? nil : encounterID, note_version: noteVersion, row_version: noteVersion ?? 1,
                vitals: noteVitals)])
    }
    func start(appointment: UUID, requestKey: UUID) async throws { }
    func diagnoses(query: String, byCode: Bool) async throws -> [DoctorDiagnosis] { [] }
    func save(encounter: UUID, note: UUID?, version: Int?, draft: DoctorConsultationDraft, diagnosis: UUID?, requestKey: UUID) async throws {
        saveKeys.append(requestKey)
        if failSave { throw URLError(.networkConnectionLost) }
        if conflictOnce { conflictOnce = false; noteVersion = (noteVersion ?? 0) + 5; throw HospitalError.conflict("El borrador cambió. Actualiza antes de guardar") }
        savedDrafts.append(draft); noteVersion = (noteVersion ?? 0) + 1
    }
    /// Simula el servidor sin supabase/doctor-consultation-six-fields.sql: exige `plan` para finalizar.
    var planRequired = false
    var notePlan: String? = "Plan"
    var noteVitals: [String: String]? = nil
    func close(encounter: UUID, note: UUID, noteVersion: Int, encounterVersion: Int) async throws {
        closeCalls += 1
        if planRequired && (savedDrafts.last?.plan ?? notePlan ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            throw HospitalError.message("Completa motivo, exploración, diagnóstico y tratamiento")
        }
    }
    func issueOrder(encounter: UUID, test: Int64, instructions: String, requestKey: UUID) async throws { }
    func prescribe(encounter: UUID, lines: [DoctorRxLine], requestKey: UUID) async throws { }
    func markRead(_ notification: DoctorNotification) async throws { }
}

struct DoctorModuleTests {
    @Test @MainActor func finishingNeverClosesWhenSaveFails() async {
        let repository = DoctorRepositoryStub()
        let model = DoctorViewModel(repository: repository)
        model.configure(facility: UUID(), identity: UUID())
        await model.refresh(); model.select(repository.appointmentID); await model.loadChart()
        repository.failSave = true
        await model.closeConsultation()
        #expect(repository.closeCalls == 0)
        #expect(model.error != nil)
        #expect(model.draft.subjective == "Motivo")
        model.clear()
        #expect(model.alerts.isEmpty && model.unreadAlerts == 0)
    }

    @Test func agendaIsChronologicalAndSplitBySection() throws {
        let calendar = DoctorClinicalRules.calendar
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 20)))
        func appointment(_ hour: Int, _ minute: Int, dayOffset: Int = 0, status: String = "scheduled", name: String) throws -> DoctorAppointment {
            let base = try #require(calendar.date(byAdding: .day, value: dayOffset, to: day))
            let start = try #require(calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base))
            return DoctorAppointment(id: UUID(), patient_id: UUID(), patient_name: name, record_number: "EXP", phone: nil, ticket_number: nil,
                period: "[\"\(DoctorDate.timestamp(start))\",\"\(DoctorDate.timestamp(start.addingTimeInterval(1800)))\")", status: status, encounter_id: nil)
        }
        let values = [try appointment(8, 30, name: "C"), try appointment(10, 0, status: "confirmed", name: "D"), try appointment(6, 0, name: "A"),
                      try appointment(7, 0, status: "in_progress", name: "B"), try appointment(9, 0, dayOffset: 1, name: "Mañana"),
                      try appointment(11, 0, status: "completed", name: "Hecha"), try appointment(12, 0, status: "cancelled", name: "Cancelada")]
        let agenda = DoctorClinicalRules.agenda(values, day: day)
        #expect(agenda.day.map(\.patient_name) == ["A", "B", "C", "D"])
        #expect(agenda.upcoming.map(\.patient_name) == ["Mañana"])
        #expect(agenda.completed.map(\.patient_name) == ["Hecha"])
        #expect(agenda.cancelled.map(\.patient_name) == ["Cancelada"])
    }

    @Test func pendingAndFinishedFiltersUseHourAndRealFinish() throws {
        let calendar = DoctorClinicalRules.calendar
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 20)))
        func at(_ hour: Int, _ minute: Int, _ offset: Int = 0) throws -> Date {
            try #require(calendar.date(bySettingHour: hour, minute: minute, second: 0, of: try #require(calendar.date(byAdding: .day, value: offset, to: day))))
        }
        func appointment(_ name: String, _ start: Date, _ status: String, finished: Date? = nil, code: String? = nil) -> DoctorAppointment {
            DoctorAppointment(id: UUID(), patient_id: UUID(), patient_name: name, record_number: "EXP-\(name)", phone: nil, ticket_number: nil,
                period: "[\"\(DoctorDate.timestamp(start))\",\"\(DoctorDate.timestamp(start.addingTimeInterval(1800)))\")",
                patient_code: code, finished_at: finished.map(DoctorDate.timestamp), status: status, encounter_id: nil)
        }
        let values = [
            appointment("Ocho", try at(8, 0), "scheduled"), appointment("Seis", try at(6, 0), "confirmed"),
            appointment("Siete", try at(7, 0), "in_progress"), appointment("Abierta ayer", try at(23, 30, -1), "in_progress"),
            appointment("Programada ayer", try at(9, 0, -1), "scheduled"), appointment("Cancelada", try at(9, 0), "cancelled"),
            appointment("No asistió", try at(10, 0), "no_show"),
            appointment("Hecha 10", try at(6, 30), "completed", finished: try at(10, 0)),
            appointment("Hecha 9", try at(7, 30), "completed", finished: try at(9, 0)),
            appointment("Tarde", try at(23, 0, -1), "completed", finished: try at(0, 20)),
            appointment("Ayer", try at(8, 0, -1), "completed", finished: try at(8, 40, -1)),
            appointment("José Pérez", try at(11, 0), "scheduled", code: "PAC-0042")]
        let now = try at(12, 0)
        #expect(DoctorClinicalRules.pending(values, day: day, now: now).map(\.patient_name) == ["Abierta ayer", "Seis", "Siete", "Ocho", "José Pérez"],
                "Hora ascendente; en atención de días previos se retoman hoy; sin canceladas ni finalizadas")
        #expect(DoctorClinicalRules.finished(values, day: day).map(\.patient_name) == ["Hecha 10", "Hecha 9", "Tarde"],
                "Por hora real de finalización, la última primero")
        #expect(DoctorClinicalRules.finished(values, day: try at(0, 0, -1)).map(\.patient_name) == ["Ayer"])
        let yesterdayPending = DoctorClinicalRules.pending(values, day: try at(0, 0, -1), now: now).map(\.patient_name)
        #expect(yesterdayPending == ["Programada ayer", "Abierta ayer"])
        let jose = try #require(values.last)
        #expect(DoctorClinicalRules.matches(jose, query: "perez") && DoctorClinicalRules.matches(jose, query: "jose perez") && DoctorClinicalRules.matches(jose, query: "pac-0042"))
        #expect(!DoctorClinicalRules.matches(jose, query: "ana"))
        let agenda = DoctorClinicalRules.agenda(values, day: day)
        #expect(!agenda.day.contains { $0.patient_name == "Programada ayer" }, "Los días previos pedidos no cuentan como citas del día")
    }

    @Test func statusesFollowOpeningAndClosing() {
        #expect(DoctorClinicalRules.statusLabel("scheduled") == "Programada")
        #expect(DoctorClinicalRules.statusLabel("confirmed") == "Programada")
        #expect(DoctorClinicalRules.statusLabel("in_progress") == "En consulta")
        #expect(DoctorClinicalRules.statusLabel("completed") == "Finalizada")
        #expect(MobileFormatting.status("in_progress") == "En consulta")
    }

    @Test func vitalsRejectTextOutOfRangeAndComputeBMI() {
        #expect(DoctorClinicalRules.sanitize("7a0,5kg", integer: false) == "70.5")
        #expect(DoctorClinicalRules.sanitize("12.5", integer: true) == "125")
        #expect(DoctorClinicalRules.vitalIssues(["weight_kg": "70.5", "height_cm": "170", "systolic": "120", "diastolic": "80"]).isEmpty)
        #expect(DoctorClinicalRules.vitalIssues(["temperature_c": "60"])["temperature_c"] != nil)
        #expect(DoctorClinicalRules.vitalIssues(["weight_kg": "0"])["weight_kg"] != nil)
        #expect(DoctorClinicalRules.vitalIssues(["height_cm": "301"])["height_cm"] != nil)
        #expect(DoctorClinicalRules.vitalIssues(["temperature_c": "24.9"])["temperature_c"] != nil)
        #expect(DoctorClinicalRules.vitals.map(\.key) == ["weight_kg", "height_cm", "temperature_c"], "Solo peso, altura y temperatura en el formulario")
        #expect(DoctorClinicalRules.vitalIssues(["systolic": "80", "diastolic": "90"]).isEmpty, "Las medidas antiguas conservadas no bloquean")
        #expect(DoctorClinicalRules.bmi(["weight_kg": "70", "height_cm": "170"]) == "24.2")
        #expect(DoctorClinicalRules.bmi(["weight_kg": "70"]) == nil)
    }

    @Test @MainActor func incompleteConsultationCannotFinish() async {
        let repository = DoctorRepositoryStub()
        let model = DoctorViewModel(repository: repository)
        model.configure(facility: UUID(), identity: UUID())
        await model.refresh(); model.select(repository.appointmentID); await model.loadChart()
        model.draft.assessment = "  "
        #expect(model.finishBlockers.contains { $0.contains("Diagnóstico") })
        #expect(!model.finishBlockers.contains { $0.contains("Plan") }, "El plan ya no es un campo del formulario")
        #expect(await model.closeConsultation() == false)
        #expect(repository.closeCalls == 0 && repository.saveKeys.isEmpty)
    }

    @Test @MainActor func finishSavesFirstThenClosesAndReturnsToAgenda() async {
        let repository = DoctorRepositoryStub()
        let model = DoctorViewModel(repository: repository)
        model.configure(facility: UUID(), identity: UUID())
        await model.refresh(); model.select(repository.appointmentID); await model.loadChart()
        model.draft.vitals = ["weight_kg": "70", "height_cm": "170"]
        #expect(model.hasUnsavedChanges)
        #expect(await model.closeConsultation())
        #expect(repository.savedDrafts.last?.vitals["weight_kg"] == "70")
        #expect(repository.closeCalls == 1)
        #expect(model.selectedAppointmentID == nil)
        #expect(model.confirmation?.contains("finalizada") == true)
    }

    @Test @MainActor func versionConflictShowsServerVersionBeforeOverwriting() async {
        let repository = DoctorRepositoryStub()
        let model = DoctorViewModel(repository: repository)
        model.configure(facility: UUID(), identity: UUID())
        await model.refresh(); model.select(repository.appointmentID); await model.loadChart()
        model.draft.objective = "Mi exploración"
        repository.conflictOnce = true
        #expect(await model.saveConsultation() == false)
        #expect(model.conflictNote != nil)
        #expect(model.draft.objective == "Mi exploración")
        #expect(await model.saveConsultation() == false, "No sobrescribe sin decisión del médico")
        await model.resolveConflict(keepMine: true)
        #expect(repository.savedDrafts.last?.objective == "Mi exploración")
        #expect(model.conflictNote == nil)
    }

    @Test @MainActor func firstOpeningPrefillsWhatThePatientSent() async throws {
        let repository = DoctorRepositoryStub()
        repository.appointments = [DoctorAppointment(id: repository.appointmentID, patient_id: repository.patientID, patient_name: "Paciente ficticio",
            record_number: "TEST", phone: nil, ticket_number: nil, period: "", status: "in_progress", encounter_id: nil, reason: "Dolor de garganta", symptoms: ["Fiebre", "Tos"])]
        let model = DoctorViewModel(repository: repository)
        model.configure(facility: UUID(), identity: UUID())
        await model.refresh(); model.select(repository.appointmentID)
        #expect(DoctorClinicalRules.seedSubjective(try #require(model.selectedAppointment)) == "Síntomas referidos por el paciente: Fiebre, Tos")
    }

    @Test func recordHistoryShowsOnlyFinishedNewestFirst() {
        func visit(_ id: Int, _ date: String, _ status: String) -> DoctorConsultation {
            DoctorConsultation(id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", id))!, started_at: date, status: status,
                subjective: nil, objective: nil, assessment: "Diagnóstico \(id)", plan: nil, note_id: nil, note_version: 1, row_version: 1)
        }
        let history = [visit(1, "2026-10-01T15:00:00Z", "closed"), visit(2, "2026-11-19T15:00:00Z", "open"), visit(3, "2026-11-10T15:00:00Z", "closed")]
        #expect(DoctorRecordRules.finishedHistory(history).map(\.assessment) == ["Diagnóstico 3", "Diagnóstico 1"], "Más reciente primero y sin consultas abiertas")
        #expect(DoctorRecordRules.text("  ") == nil && DoctorRecordRules.text(nil) == nil, "Campos vacíos no se presentan como datos")
        let encounter = UUID()
        let lab = DoctorPatientLab(id: UUID(), test_name: "Examen", reason: "Motivo", status: "completado", ordered_at: "2026-11-10T15:00:00Z",
            result_summary: "Resultado", completed_at: nil, encounter_id: encounter)
        #expect(DoctorRecordRules.labs([lab], encounter: encounter).count == 1)
        #expect(DoctorRecordRules.labs([lab], encounter: UUID()).isEmpty, "No mezcla exámenes de otras consultas")
        #expect(!DoctorRecordRules.publishedResult(lab), "Sin publicación no se muestra el resultado")
    }

    @Test @MainActor func recordSearchWaitsAndDoesNotRepeatQueries() async {
        let repository = DoctorRepositoryStub()
        let model = DoctorViewModel(repository: repository)
        model.configure(facility: UUID(), identity: UUID())
        model.patientQuery = "Pac"
        let first = Task { await model.searchPatients(debounce: .milliseconds(200)) }
        model.patientQuery = "Paciente"
        first.cancel()
        await model.searchPatients(debounce: .milliseconds(10))
        #expect(repository.patientQueries == ["Paciente"], "La búsqueda pendiente se descarta al seguir escribiendo")
        await model.searchPatients(debounce: .milliseconds(10))
        #expect(repository.patientQueries == ["Paciente"], "El mismo texto no se consulta otra vez")
    }

    @Test func patientHistoryGroupsOnlyRealFields() {
        let item = MobileItem(id: UUID(), title: "Medicina general", subtitle: nil, status: "completed", event_at: "2026-11-10T15:00:00Z", row_version: 0,
            details: [MobileField(label: "Médico", value: "Médico autor"), MobileField(label: "Motivo de consulta", value: "Dolor de garganta"),
                      MobileField(label: "Diagnóstico", value: "Faringitis"), MobileField(label: "Observaciones", value: " "),
                      MobileField(label: "Peso (kg)", value: "61.5"), MobileField(label: "Receta REC-1", value: "Medicamento 500 mg")],
            action: nil, document_id: nil)
        let record = PatientHistoryRecord.from(item)
        #expect(record.doctor == "Médico autor" && record.reason == "Dolor de garganta" && record.diagnosis == "Faringitis")
        #expect(record.groups.map({ $0.title }) == ["Datos físicos", "Evaluación médica", "Recetas"])
        #expect(!record.groups.flatMap({ $0.fields }).contains(where: { $0.label == "Observaciones" }), "No muestra campos vacíos")
    }

    @Test func consultationCanOpenAtAnyTimeWhileTesting() {
        let future = DoctorDate.timestamp(Date().addingTimeInterval(3 * 86400))
        let appointment = DoctorAppointment(id: UUID(), patient_id: UUID(), patient_name: "Paciente ficticio", record_number: "TEST", phone: nil,
            ticket_number: nil, period: "[\"\(future)\",\"\(future)\")", status: "scheduled", encounter_id: nil)
        #expect(DoctorClinicalRules.openingLeadMinutes == nil)
        #expect(DoctorConsultationFields.openingBlocker(appointment) == nil, "Una cita de dentro de 3 días puede abrirse")
        let cancelled = DoctorAppointment(id: UUID(), patient_id: UUID(), patient_name: "Paciente ficticio", record_number: "TEST", phone: nil,
            ticket_number: nil, period: "", status: "cancelled", encounter_id: nil)
        #expect(DoctorConsultationFields.openingBlocker(cancelled) != nil, "Las canceladas siguen sin abrirse")
        #expect(DoctorClinicalRules.startError("La cita todavía no puede iniciarse o ya finalizó") == DoctorClinicalRules.pendingStartMigration)
    }

    @Test @MainActor func sixFieldsSaveAndKeepOlderMeasurements() async {
        let repository = DoctorRepositoryStub()
        repository.notePlan = nil
        repository.noteVitals = ["systolic": "118", "diastolic": "76"]
        let model = DoctorViewModel(repository: repository)
        model.configure(facility: UUID(), identity: UUID())
        await model.refresh(); model.select(repository.appointmentID); await model.loadChart()
        model.draft.subjective = "Fiebre de dos días"; model.draft.assessment = "Faringitis aguda"; model.draft.objective = "Faringe eritematosa"
        model.draft.vitals["weight_kg"] = "70.5"; model.draft.vitals["height_cm"] = "170"; model.draft.vitals["temperature_c"] = "38.2"
        #expect(model.finishBlockers.isEmpty)
        #expect(await model.saveConsultation())
        let saved = repository.savedDrafts.last
        #expect(saved?.subjective == "Fiebre de dos días" && saved?.assessment == "Faringitis aguda" && saved?.objective == "Faringe eritematosa")
        #expect(saved?.vitals == ["weight_kg": "70.5", "height_cm": "170", "temperature_c": "38.2", "systolic": "118", "diastolic": "76"])
        #expect(saved?.plan == "", "No inventa un plan")
    }

    @Test @MainActor func finishExplainsPendingMigrationWithoutClosing() async {
        let repository = DoctorRepositoryStub()
        repository.notePlan = nil
        repository.planRequired = true
        let model = DoctorViewModel(repository: repository)
        model.configure(facility: UUID(), identity: UUID())
        await model.refresh(); model.select(repository.appointmentID); await model.loadChart()
        #expect(await model.closeConsultation() == false)
        #expect(model.error == DoctorClinicalRules.pendingFinishMigration)
        #expect(model.selectedAppointmentID == repository.appointmentID, "Sigue en la consulta sin perder datos")
        repository.planRequired = false
        #expect(await model.closeConsultation())
    }

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
