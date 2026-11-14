import Foundation
import Combine
import PostgREST

@MainActor
final class DoctorViewModel: ObservableObject {
    @Published private(set) var workspace: DoctorWorkspace?
    @Published private(set) var labCatalog: [DoctorLabTest] = []
    @Published private(set) var labCatalogLoading = false
    @Published private(set) var labCatalogError: String?
    @Published var labQuery = ""
    @Published var labCategory = "all"
    @Published var selectedLabIDs: Set<Int64> = []
    @Published private(set) var pendingLabs: DoctorLabSelection?
    @Published private(set) var ownLabOrders: [DoctorPatientLab] = []
    @Published private(set) var ownLabPage: DoctorPatientLabPage?
    @Published private(set) var ownLabsLoading = false
    @Published private(set) var ownLabsError: String?
    private var labGeneration = UUID()
    @Published private(set) var admissions: [DoctorAdmission] = []
    @Published private(set) var admissionsPage: DoctorAdmissionsPage?
    @Published private(set) var admissionsLoading = false
    @Published private(set) var admissionsError: String?
    @Published var admissionForm = false
    @Published var admissionCategory = ""
    @Published var admissionPriority = "normal"
    @Published var admissionReason = ""
    @Published var admissionObservations = ""
    @Published private(set) var pendingAdmission: DoctorAdmissionInput?
    private var admissionsGeneration = UUID()
    @Published private(set) var patientDirectory: [DoctorAssignedPatient] = []
    @Published private(set) var directoryPage: DoctorPatientDirectoryPage?
    @Published private(set) var directoryLoading = false
    @Published private(set) var directoryError: String?
    @Published var patientQuery = ""
    @Published private(set) var selectedPatient: DoctorAssignedPatient?
    @Published private(set) var patientLabs: [DoctorPatientLab] = []
    @Published private(set) var patientLabPage: DoctorPatientLabPage?
    @Published private(set) var patientLabsLoading = false
    @Published private(set) var patientLabsError: String?
    private var directoryGeneration = UUID()
    @Published private(set) var chart: DoctorPatientChart?
    @Published private(set) var contextChart: DoctorPatientChart?
    @Published private(set) var loading = false
    @Published private(set) var loadingChart = false
    @Published private(set) var saving = false
    @Published private(set) var error: String?
    @Published private(set) var confirmation: String?
    @Published var selectedAppointmentID: UUID?
    @Published var selectedTestID: Int64?
    @Published var statusFilter = "all"
    @Published var rxMedication: UUID?
    @Published var rxDose = ""
    @Published var rxUnit = ""
    @Published var rxFrequency = ""
    @Published var rxQuantity = ""
    @Published var rxDays = ""
    @Published var rxRoute = "oral"
    @Published var rxInstructions = ""
    @Published var rxLines: [DoctorRxLine] = []
    @Published var draft = DoctorConsultationDraft()
    @Published var instructions = ""
    @Published var diagnosisQuery = ""
    @Published var diagnosisByCode = false
    @Published var selectedDiagnosis: UUID?
    @Published private(set) var diagnoses: [DoctorDiagnosis] = []
    @Published private(set) var searchingDiagnoses = false
    @Published var day = Date()
    @Published var filterDates = false
    @Published var historyFrom = Calendar.current.startOfDay(for: Date())
    @Published var historyTo = Date()
    @Published var historyQuery = ""
    private let repository: any DoctorRepositoryProtocol
    private var facility: UUID?
    private var identity: UUID?
    private var generation = UUID()
    private var selectionGeneration = UUID()
    private var startKey = UUID()
    private var saveKey = UUID()
    private var orderKey = UUID()
    private var rxKey = UUID()
    private var draftInitialized = false
    private var draftNoteID: UUID?
    private var draftNoteVersion: Int?

    init(repository: any DoctorRepositoryProtocol) { self.repository = repository }

    var selectedAppointment: DoctorAppointment? {
        workspace?.appointments.first { $0.id == selectedAppointmentID }
    }
    var activeConsultation: DoctorConsultation? {
        guard let encounter = selectedAppointment?.encounter_id ?? selectedPatient?.active_encounter_id else { return nil }
        return contextChart?.history.first { $0.id == encounter }
    }
    var canEditConsultation: Bool {
        activeConsultation?.status == "open"
    }

    func configure(facility: UUID, identity: UUID) {
        guard self.facility != facility || self.identity != identity else { return }
        clear()
        self.facility = facility
        self.identity = identity
    }

    func clear() {
        labGeneration = UUID(); labCatalog = []; labCatalogLoading = false; labCatalogError = nil
        ownLabOrders = []; ownLabPage = nil; ownLabsLoading = false; ownLabsError = nil
        pendingLabs = nil; selectedLabIDs = []; labQuery = ""; labCategory = "all"
        admissionsGeneration = UUID(); admissions = []; admissionsPage = nil; admissionsLoading = false; admissionsError = nil
        admissionForm = false; admissionCategory = ""; admissionPriority = "normal"; admissionReason = ""; admissionObservations = ""; pendingAdmission = nil
        directoryGeneration = UUID(); patientDirectory = []; directoryPage = nil; directoryLoading = false
        directoryError = nil; patientQuery = ""; selectedPatient = nil; patientLabs = []; patientLabPage = nil
        patientLabsLoading = false; patientLabsError = nil
        generation = UUID(); selectionGeneration = UUID()
        facility = nil; identity = nil
        workspace = nil; chart = nil; contextChart = nil; selectedAppointmentID = nil
        selectedTestID = nil; draft = DoctorConsultationDraft(); instructions = ""
        historyQuery = ""; filterDates = false; day = Date()
        loading = false; loadingChart = false; saving = false; error = nil; confirmation = nil
        startKey = UUID(); saveKey = UUID(); orderKey = UUID()
        diagnosisQuery = ""; selectedDiagnosis = nil; diagnoses = []; searchingDiagnoses = false
        draftInitialized = false; draftNoteID = nil; draftNoteVersion = nil
        clearPrescription(); statusFilter = "all"
    }

    func refresh() async {
        guard let facility, !loading, !saving else { return }
        let scope = generation
        let from = Calendar.current.startOfDay(for: day)
        guard let to = Calendar.current.date(byAdding: .day, value: 1, to: from) else { return }
        loading = true; error = nil
        defer { if generation == scope { loading = false } }
        do {
            let value = try await repository.workspace(facility: facility, from: from, to: to)
            guard scope == generation, !Task.isCancelled else { return }
            workspace = value
            if let selectedAppointmentID, !value.appointments.contains(where: { $0.id == selectedAppointmentID }) {
                let patient = selectedPatient; select(nil); selectedPatient = patient
            }
        } catch {
            guard scope == generation else { return }
            workspace = nil; chart = nil; contextChart = nil
            self.error = Self.describe(error)
        }
    }

    func select(_ appointment: UUID?) {
        guard !saving else { return }
        selectedPatient = nil; patientLabs = []; patientLabPage = nil; patientLabsError = nil; patientLabsLoading = false
        if pendingLabs == nil { selectedLabIDs = [] }
        selectionGeneration = UUID()
        selectedAppointmentID = appointment; chart = nil; contextChart = nil
        draft = DoctorConsultationDraft(); instructions = ""; selectedTestID = nil
        error = nil; confirmation = nil; loadingChart = false
        startKey = UUID(); saveKey = UUID(); orderKey = UUID()
        diagnosisQuery = ""; selectedDiagnosis = nil; diagnoses = []; searchingDiagnoses = false
        draftInitialized = false; draftNoteID = nil; draftNoteVersion = nil
        clearPrescription()
    }

    func searchDiagnoses() async {
        let query = diagnosisQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2, query.count <= 120, !searchingDiagnoses, !saving else { return }
        let scope = generation, selection = selectionGeneration
        searchingDiagnoses = true
        defer { if scope == generation && selection == selectionGeneration { searchingDiagnoses = false } }
        do {
            let values = try await repository.diagnoses(query: query, byCode: diagnosisByCode)
            guard scope == generation, selection == selectionGeneration else { return }
            diagnoses = values
        } catch { if scope == generation && selection == selectionGeneration { self.error = Self.describe(error) } }
    }

    func loadChart(filtered: Bool = false) async {
        guard let patient = selectedPatient?.id ?? selectedAppointment?.patient_id else { return }
        let scope = generation
        let selection = selectionGeneration
        guard !filtered || !filterDates || historyFrom <= historyTo else {
            error = "La fecha inicial no puede ser posterior a la final."; return
        }
        loadingChart = true; error = nil
        defer { if scope == generation && selection == selectionGeneration { loadingChart = false } }
        do {
            let value = try await repository.chart(patient: patient,
                from: filtered && filterDates ? historyFrom : nil,
                to: filtered && filterDates ? historyTo : nil,
                query: filtered ? historyQuery.trimmingCharacters(in: .whitespacesAndNewlines) : "")
            guard scope == generation, selection == selectionGeneration, !Task.isCancelled else { return }
            chart = value
            if !filtered {
                contextChart = value
                if !draftInitialized, let note = activeConsultation {
                    draft = DoctorConsultationDraft(subjective: note.subjective ?? "", objective: note.objective ?? "",
                        assessment: note.assessment ?? "", plan: note.plan ?? "", diagnosis_code: note.diagnosis_code ?? "", vitals: note.vitals ?? [:])
                    draftNoteID = note.note_id; draftNoteVersion = note.note_version; draftInitialized = true
                }
            }
        } catch {
            guard scope == generation, selection == selectionGeneration else { return }
            chart = nil
            if !filtered { contextChart = nil }
            self.error = Self.describe(error)
        }
    }

    /// doctor_chart aplica el médico autenticado en el servidor; no se acepta un médico elegido por el cliente.
    func patientHistory(patient: UUID, from: Date?, to: Date?) async throws -> [DoctorConsultation] {
        guard workspace?.appointments.contains(where: { $0.patient_id == patient }) == true else { throw CancellationError() }
        let scope = generation
        let value = try await repository.chart(patient: patient, from: from, to: to, query: "")
        guard generation == scope, !Task.isCancelled else { throw CancellationError() }
        return value.history
    }
    func loadPatients(more: Bool = false) async {
        guard facility != nil, !saving, !more || (!directoryLoading && directoryPage?.has_more == true) else { return }
        let query = patientQuery.trimmingCharacters(in:.whitespacesAndNewlines)
        guard query.count<=120 else { directoryError="La búsqueda admite hasta 120 caracteres."; return }
        let scope=generation, request=UUID(); directoryGeneration=request
        directoryLoading=true; directoryError=nil
        if !more { patientDirectory=[]; directoryPage=nil }
        defer { if scope==generation && request==directoryGeneration { directoryLoading=false } }
        do {
            let page=try await repository.patients(query:query,offset:more ? directoryPage?.next_offset ?? 0 : 0)
            guard scope==generation, request==directoryGeneration, !Task.isCancelled else { return }
            patientDirectory=more ? patientDirectory+page.patients : page.patients; directoryPage=page
        } catch { if scope==generation && request==directoryGeneration { directoryError=Self.describe(error) } }
    }
    func openPatient(_ patient: DoctorAssignedPatient) {
        guard !saving else { return }
        let appointment=workspace?.appointments.first { $0.patient_id==patient.id && $0.encounter_id==patient.active_encounter_id && patient.active_encounter_id != nil }
        select(appointment?.id); selectedPatient=patient
    }
    func dismissPatient() { select(nil) }
    func adoptAppointmentPatient() {
        guard !saving, selectedPatient == nil, let patient=selectedAppointment?.patient_id else { return }
        selectedPatient=patientDirectory.first { $0.id==patient }
        if selectedPatient == nil, let appointment=selectedAppointment {
            selectedPatient=DoctorAssignedPatient(id:patient,full_name:appointment.patient_name,record_number:appointment.record_number,
                dui:chart?.patient.identification,email:chart?.patient.email,phone:appointment.phone,birth_date:chart?.patient.birth_date,
                age:appointment.age,active_encounter_id:appointment.encounter_id)
        }
    }
    func loadPatientLabs(more: Bool = false) async {
        guard let patient=selectedPatient?.id ?? selectedAppointment?.patient_id, !saving,
              !more || (!patientLabsLoading && patientLabPage?.has_more==true) else { return }
        let scope=generation, selection=selectionGeneration
        patientLabsLoading=true; patientLabsError=nil
        if !more { patientLabs=[]; patientLabPage=nil }
        defer { if scope==generation && selection==selectionGeneration { patientLabsLoading=false } }
        do {
            let page=try await repository.patientLabs(patient:patient,offset:more ? patientLabPage?.next_offset ?? 0 : 0)
            guard scope==generation, selection==selectionGeneration, !Task.isCancelled else { return }
            patientLabs=more ? patientLabs+page.items : page.items; patientLabPage=page
        } catch { if scope==generation && selection==selectionGeneration { patientLabsError=Self.describe(error) } }
    }

    func loadAdmissions(more: Bool = false) async {
        guard facility != nil, !saving, !more || (!admissionsLoading && admissionsPage?.has_more == true) else { return }
        let scope = generation, request = UUID(); admissionsGeneration = request
        admissionsLoading = true; admissionsError = nil
        defer { if scope == generation && request == admissionsGeneration { admissionsLoading = false } }
        do {
            let page = try await repository.admissions(offset: more ? admissionsPage?.next_offset ?? 0 : 0)
            guard scope == generation, request == admissionsGeneration, !Task.isCancelled else { return }
            admissions = more ? admissions + page.items : page.items; admissionsPage = page
        } catch {
            if scope == generation && request == admissionsGeneration { admissions = []; admissionsError = Self.describe(error) }
        }
    }
    var canRequestAdmission: Bool {
        pendingAdmission != nil || ((selectedPatient?.id ?? selectedAppointment?.patient_id) != nil &&
            admissionsPage?.categories.contains(admissionCategory) == true && admissionsPage?.priorities.contains(admissionPriority) == true &&
            !admissionReason.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && admissionReason.count <= 10000 && admissionObservations.count <= 10000)
    }
    func requestAdmission() async {
        guard canRequestAdmission, !saving, !loadingChart else { return }
        if pendingAdmission == nil, let patient = selectedPatient?.id ?? selectedAppointment?.patient_id {
            pendingAdmission = DoctorAdmissionInput(patient:patient, patientName:selectedPatient?.full_name ?? selectedAppointment?.patient_name ?? "",
                recordNumber:selectedPatient?.record_number ?? selectedAppointment?.record_number, encounter:activeConsultation?.id, category:admissionCategory,
                priority:admissionPriority, reason:admissionReason.trimmingCharacters(in:.whitespacesAndNewlines),
                observations:admissionObservations.trimmingCharacters(in:.whitespacesAndNewlines), key:UUID())
        }
        guard let input = pendingAdmission else { return }
        let scope = generation; saving = true; admissionsError = nil; confirmation = nil
        do {
            try await repository.requestAdmission(input)
            guard scope == generation else { return }
            pendingAdmission = nil; admissionForm = false; admissionReason = ""; admissionObservations = ""; admissionCategory = ""; admissionPriority = "normal"
            saving = false; confirmation = "Solicitud enviada a recepción. Aún no se ha asignado habitación ni cama."
            await loadAdmissions()
        } catch {
            guard scope == generation else { return }
            saving = false; admissionsError = Self.describe(error)
            // Known server rejection means no commit; transport failures keep the exact payload/key for a safe retry.
            if let failure = error as? BackendFailure, [400,401,403,409,422].contains(failure.status) { pendingAdmission = nil }
            if error is HospitalError { pendingAdmission = nil }
        }
    }

    func startConsultation() async {
        guard let appointment = selectedAppointment, appointment.encounter_id == nil else { return }
        let key = startKey
        let scope = generation
        await mutate(success: "Consulta iniciada.") {
            try await self.repository.start(appointment: appointment.id, requestKey: key)
            if self.generation == scope { self.startKey = UUID(); self.draftInitialized = false }
        }
    }

    func saveConsultation() async {
        guard let encounter = activeConsultation, canEditConsultation, draft.canSave else { return }
        let values = draft
        let key = saveKey
        let diagnosis = selectedDiagnosis
        let noteID = draftNoteID, version = draftNoteVersion, scope = generation
        await mutate(success: "Consulta guardada como borrador.") {
            try await self.repository.save(encounter: encounter.id, note: noteID,
                version: version, draft: values, diagnosis: diagnosis, requestKey: key)
            if self.generation == scope { self.saveKey = UUID(); self.draftInitialized = false }
        }
    }

    func closeConsultation() async {
        guard let encounter = activeConsultation, canEditConsultation,
              let note = encounter.note_id, let version = encounter.note_version else { return }
        guard draft.subjective == (encounter.subjective ?? ""), draft.objective == (encounter.objective ?? ""),
              draft.assessment == (encounter.assessment ?? ""), draft.plan == (encounter.plan ?? ""),
              draft.diagnosis_code == (encounter.diagnosis_code ?? ""), draft.vitals == (encounter.vitals ?? [:]), rxLines.isEmpty else {
            error = "Guarda los cambios antes de firmar y cerrar la consulta."; return
        }
        await mutate(success: "Consulta firmada y cerrada.") {
            try await self.repository.close(encounter: encounter.id, note: note,
                noteVersion: version, encounterVersion: encounter.row_version)
        }
    }

    var filteredLabTests: [DoctorLabTest] {
        labCatalog.filter { (labCategory == "all" || ($0.category ?? "Sin categoría") == labCategory) &&
            (labQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(labQuery)) }
    }
    func loadLabCatalog() async {
        guard facility != nil, !labCatalogLoading else { return }
        let scope=generation; labCatalogLoading=true; labCatalogError=nil
        defer { if scope==generation { labCatalogLoading=false } }
        do {
            let tests=try await repository.labCatalog()
            guard scope==generation, !Task.isCancelled else { return }
            labCatalog=tests
        } catch { if scope==generation { labCatalogError=Self.describe(error) } }
    }
    func loadOwnLabOrders(more:Bool=false) async {
        guard facility != nil, !saving, !more || (!ownLabsLoading && ownLabPage?.has_more==true) else { return }
        let scope=generation, request=UUID(); labGeneration=request; ownLabsLoading=true; ownLabsError=nil
        defer { if scope==generation && request==labGeneration { ownLabsLoading=false } }
        do {
            let page=try await repository.labOrders(offset:more ? ownLabPage?.next_offset ?? 0 : 0)
            guard scope==generation, request==labGeneration, !Task.isCancelled else { return }
            ownLabOrders=more ? ownLabOrders+page.items : page.items; ownLabPage=page
        } catch { if scope==generation && request==labGeneration { ownLabOrders=[]; ownLabsError=Self.describe(error) } }
    }
    var canIssueLabs: Bool {
        pendingLabs != nil || (canEditConsultation && !selectedLabIDs.isEmpty && selectedLabIDs.count<=30 &&
            selectedLabIDs.allSatisfy { id in labCatalog.contains { $0.id==id } } &&
            !instructions.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && instructions.count<=10000)
    }
    func issueSelectedLabs() async {
        guard canIssueLabs, !saving, !loadingChart else { return }
        if pendingLabs == nil, let encounter=activeConsultation {
            pendingLabs=DoctorLabSelection(encounter:encounter.id,patientName:selectedPatient?.full_name ?? selectedAppointment?.patient_name ?? "",
                recordNumber:selectedPatient?.record_number ?? selectedAppointment?.record_number,tests:selectedLabIDs.sorted(),
                reason:instructions.trimmingCharacters(in:.whitespacesAndNewlines),key:UUID())
        }
        guard let input=pendingLabs else { return }
        let scope=generation; saving=true; error=nil; confirmation=nil
        do {
            try await repository.issueLabs(input)
            guard scope==generation else { return }
            pendingLabs=nil; selectedLabIDs=[]; instructions=""; saving=false
            confirmation="\(input.tests.count) exámenes enviados al laboratorio."
            await loadOwnLabOrders(); await loadPatientLabs()
        } catch {
            guard scope==generation else { return }
            saving=false; self.error=Self.describe(error)
            if error is HospitalError { pendingLabs=nil }
            if let failure=error as? BackendFailure, [400,401,403,409,422].contains(failure.status) { pendingLabs=nil }
        }
    }

    func issueOrder() async {
        guard let encounter = activeConsultation, canEditConsultation, let test = selectedTestID,
              workspace?.tests.contains(where: { $0.id == test }) == true,
              !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, instructions.count <= 10000 else { return }
        let key = orderKey
        let text = instructions
        let scope = generation
        await mutate(success: "Orden de laboratorio emitida.") {
            try await self.repository.issueOrder(encounter: encounter.id, test: test, instructions: text, requestKey: key)
            if self.generation == scope {
                self.orderKey = UUID(); self.instructions = ""; self.selectedTestID = nil
            }
        }
        if selectedPatient != nil, confirmation != nil { await loadPatientLabs() }
    }

    func markRead(_ notification: DoctorNotification) async {
        guard notification.read_at == nil else { return }
        await mutate(success: "Notificación marcada como leída.", reloadChart: false) {
            try await self.repository.markRead(notification)
        }
    }
    private func clearPrescription() {
        rxKey = UUID(); rxMedication = nil; rxDose = ""; rxUnit = ""; rxFrequency = ""; rxQuantity = ""
        rxDays = ""; rxRoute = "oral"; rxInstructions = ""; rxLines = []
    }
    func addMedication() {
        guard canEditConsultation, !saving, rxLines.count < 30,
              let medication = workspace?.medications?.first(where: { $0.id == rxMedication }),
              let dose = Decimal(string: rxDose.replacingOccurrences(of: ",", with: ".")), dose > 0, dose <= 100000,
              !rxUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, rxUnit.count <= 40,
              let frequency = Int(rxFrequency), (1...720).contains(frequency),
              let quantity = Int(rxQuantity), (1...10000).contains(quantity), let days = Int(rxDays), (1...365).contains(days),
              ["oral","inyectable"].contains(rxRoute), !rxInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, rxInstructions.count <= 2000 else {
            error = "Completa medicamento, dosis, unidad, frecuencia, vía, cantidad, duración e indicaciones válidas."; return
        }
        rxLines.append(DoctorRxLine(medication: medication, dose: dose, unit: rxUnit, frequency: frequency, route: rxRoute,
            quantity: quantity, days: days, instructions: rxInstructions))
        rxMedication = nil; rxDose = ""; rxUnit = ""; rxFrequency = ""; rxQuantity = ""; rxDays = ""; rxInstructions = ""; error = nil
    }
    func issuePrescription() async {
        guard canEditConsultation, let encounter = activeConsultation, !rxLines.isEmpty else { return }
        let lines = rxLines, key = rxKey, scope = generation
        await mutate(success: "Receta emitida por el médico de esta consulta.") {
            try await self.repository.prescribe(encounter: encounter.id, lines: lines, requestKey: key)
            if self.generation == scope { self.clearPrescription() }
        }
    }

    private func mutate(success: String, reloadChart: Bool = true, operation: () async throws -> Void) async {
        guard !saving, !loading, !loadingChart, facility != nil else { return }
        let scope = generation
        saving = true; error = nil; confirmation = nil
        do {
            try await operation()
            guard scope == generation else { return }
            confirmation = success
            saving = false
            await refresh()
            if reloadChart { await loadChart() }
        } catch {
            guard scope == generation else { return }
            saving = false
            self.error = Self.describe(error)
        }
    }

    static func describe(_ error: Error) -> String {
        if let known = error as? HospitalError { return known.localizedDescription }
        if let known = error as? BackendFailure { return known.localizedDescription }
        if error is CancellationError { return "La operación se canceló." }
        if let network = error as? URLError {
            return network.code == .notConnectedToInternet ? "Sin conexión. Revisa tu red e inténtalo de nuevo." : "No se pudo completar la conexión con el hospital."
        }
        if let database = error as? PostgrestError {
            switch database.code {
            case "PGRST301", "PGRST302", "PGRST303", "PT401": return "La sesión ya no es válida. Cierra sesión e inicia sesión de nuevo."
            case "42501", "PT403": return "Se requiere autorización clínica y un vínculo asistencial vigente para esta operación."
            case "PGRST202": return "El módulo médico necesita las funciones SQL indicadas en la guía de instalación."
            case "40001", "23505", "PT409": return "El registro cambió o ya existe. Actualiza antes de continuar."
            case "23514", "22023", "PT400", "PT422": return "El estado de la atención o los datos no permiten esta operación. Revisa el registro antes de continuar."
            default: return "No se pudo guardar o consultar la información. Verifica los datos y actualiza la pantalla."
            }
        }
        return "No se pudo completar la operación. Actualiza la pantalla e inténtalo de nuevo."
    }
}
