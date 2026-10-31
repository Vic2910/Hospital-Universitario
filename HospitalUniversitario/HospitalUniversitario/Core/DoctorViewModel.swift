import Foundation
import Combine
import PostgREST

@MainActor
final class DoctorViewModel: ObservableObject {
    @Published private(set) var workspace: DoctorWorkspace?
    @Published private(set) var chart: DoctorPatientChart?
    @Published private(set) var contextChart: DoctorPatientChart?
    @Published private(set) var loading = false
    @Published private(set) var loadingChart = false
    @Published private(set) var saving = false
    @Published private(set) var error: String?
    @Published private(set) var confirmation: String?
    @Published var selectedAppointmentID: UUID?
    @Published var selectedTestID: UUID?
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
    private var draftInitialized = false
    private var draftNoteID: UUID?
    private var draftNoteVersion: Int?

    init(repository: any DoctorRepositoryProtocol) { self.repository = repository }

    var selectedAppointment: DoctorAppointment? {
        workspace?.appointments.first { $0.id == selectedAppointmentID }
    }
    var activeConsultation: DoctorConsultation? {
        guard let encounter = selectedAppointment?.encounter_id else { return nil }
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
        generation = UUID(); selectionGeneration = UUID()
        facility = nil; identity = nil
        workspace = nil; chart = nil; contextChart = nil; selectedAppointmentID = nil
        selectedTestID = nil; draft = DoctorConsultationDraft(); instructions = ""
        historyQuery = ""; filterDates = false; day = Date()
        loading = false; loadingChart = false; saving = false; error = nil; confirmation = nil
        startKey = UUID(); saveKey = UUID(); orderKey = UUID()
        diagnosisQuery = ""; selectedDiagnosis = nil; diagnoses = []; searchingDiagnoses = false
        draftInitialized = false; draftNoteID = nil; draftNoteVersion = nil
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
                select(nil)
            }
        } catch {
            guard scope == generation else { return }
            workspace = nil; chart = nil; contextChart = nil
            self.error = Self.describe(error)
        }
    }

    func select(_ appointment: UUID?) {
        guard !saving else { return }
        selectionGeneration = UUID()
        selectedAppointmentID = appointment; chart = nil; contextChart = nil
        draft = DoctorConsultationDraft(); instructions = ""; selectedTestID = nil
        error = nil; confirmation = nil; loadingChart = false
        startKey = UUID(); saveKey = UUID(); orderKey = UUID()
        diagnosisQuery = ""; selectedDiagnosis = nil; diagnoses = []; searchingDiagnoses = false
        draftInitialized = false; draftNoteID = nil; draftNoteVersion = nil
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
        guard let patient = selectedAppointment?.patient_id else { return }
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
                        assessment: note.assessment ?? "", plan: note.plan ?? "")
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
        guard let encounter = activeConsultation, canEditConsultation, draft.isValid else { return }
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
              draft.assessment == (encounter.assessment ?? ""), draft.plan == (encounter.plan ?? "") else {
            error = "Guarda los cambios antes de firmar y cerrar la consulta."; return
        }
        await mutate(success: "Consulta firmada y cerrada.") {
            try await self.repository.close(encounter: encounter.id, note: note,
                noteVersion: version, encounterVersion: encounter.row_version)
        }
    }

    func issueOrder() async {
        guard let encounter = activeConsultation, canEditConsultation, let test = selectedTestID,
              workspace?.tests.contains(where: { $0.id == test }) == true,
              instructions.count <= 10000 else { return }
        let key = orderKey
        let text = instructions
        let scope = generation
        await mutate(success: "Orden de laboratorio emitida.") {
            try await self.repository.issueOrder(encounter: encounter.id, test: test, instructions: text, requestKey: key)
            if self.generation == scope {
                self.orderKey = UUID(); self.instructions = ""; self.selectedTestID = nil
            }
        }
    }

    func markRead(_ notification: DoctorNotification) async {
        guard notification.read_at == nil else { return }
        await mutate(success: "Notificación marcada como leída.", reloadChart: false) {
            try await self.repository.markRead(notification)
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
