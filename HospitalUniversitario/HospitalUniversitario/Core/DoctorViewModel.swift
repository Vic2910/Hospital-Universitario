import Foundation
import Combine
import PostgREST
import UserNotifications

@MainActor
final class DoctorViewModel: ObservableObject {
    @Published private(set) var alerts: [DoctorNotification] = []
    @Published private(set) var unreadAlerts = 0
    @Published private(set) var alertsHaveMore = false
    @Published private(set) var alertsError: String?
    @Published private(set) var notificationMessage: String?
    private var loadingAlerts = false
    private let notificationPrefix = "hospital.doctor."
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
    // Ambulancia: estado de la unidad, traslados visibles y formulario de solicitud (request_medical_transport).
    @Published private(set) var transportBoard: DoctorTransportBoard?
    @Published private(set) var transportsLoading = false
    @Published private(set) var transportsError: String?
    @Published var transportForm = false
    @Published var transportContact = ""
    @Published var transportPhone = ""
    @Published var transportOrigin = ""
    @Published var transportDestination = ""
    @Published var transportReason = ""
    @Published var transportPriority = "normal"
    @Published private(set) var pendingTransport: DoctorTransportInput?
    private var transportsGeneration = UUID()
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
    /// Hospitalizaciones del expediente abierto (mismo episodio que el paciente ve en Habitaciones).
    @Published private(set) var patientStays: PatientHospitalizations?
    @Published private(set) var patientStaysError: String?
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
    /// Agenda: "pending" (PENDIENTES) o "finished" (FINALIZADAS). Solo cambia la presentación, nunca los estados.
    @Published var statusFilter = "pending"
    /// Último valor de public.planning_revision visto: sube con cada cambio en appointments.
    private var planningRevision: Int64?
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
    private var lastFailure: Error?
    /// Última versión guardada en el servidor para la consulta abierta (base de "Cambios pendientes").
    @Published private(set) var savedDraft: DoctorConsultationDraft?
    @Published private(set) var saveState: SaveState = .idle
    /// Versión real del servidor cuando otra sesión guardó antes; se muestra antes de permitir sobrescribir.
    @Published private(set) var conflictNote: DoctorConsultation?
    enum SaveState: Equatable { case idle, saving, saved, failed(String) }
    /// Días de agenda solicitados a doctor_native_workspace (máximo del servidor: 32).
    static let agendaDays = 14

    init(repository: any DoctorRepositoryProtocol) { self.repository = repository }

    var hasUnsavedChanges: Bool { savedDraft != nil && savedDraft != draft }
    var vitalIssues: [String: String] { DoctorClinicalRules.vitalIssues(draft.vitals) }
    /// Citas del día elegido; los contadores del panel no mezclan días posteriores.
    var dayAppointments: [DoctorAppointment] {
        let calendar = DoctorClinicalRules.calendar
        return (workspace?.appointments ?? []).filter { $0.startDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }
    var agenda: DoctorClinicalRules.Agenda { DoctorClinicalRules.agenda(workspace?.appointments ?? [], day: day) }
    var pendingAppointments: [DoctorAppointment] { DoctorClinicalRules.pending(workspace?.appointments ?? [], day: day) }
    var finishedAppointments: [DoctorAppointment] { DoctorClinicalRules.finished(workspace?.appointments ?? [], day: day) }

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
        alerts = []; unreadAlerts = 0; alertsHaveMore = false; alertsError = nil; notificationMessage = nil
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        labGeneration = UUID(); labCatalog = []; labCatalogLoading = false; labCatalogError = nil
        ownLabOrders = []; ownLabPage = nil; ownLabsLoading = false; ownLabsError = nil
        pendingLabs = nil; selectedLabIDs = []; labQuery = ""; labCategory = "all"
        admissionsGeneration = UUID(); admissions = []; admissionsPage = nil; admissionsLoading = false; admissionsError = nil
        admissionForm = false; admissionCategory = ""; admissionPriority = "normal"; admissionReason = ""; admissionObservations = ""; pendingAdmission = nil
        transportsGeneration = UUID(); transportBoard = nil; transportsLoading = false; transportsError = nil; resetTransportForm()
        directoryGeneration = UUID(); patientDirectory = []; directoryPage = nil; directoryLoading = false
        directoryError = nil; patientQuery = ""; lastDirectoryQuery = nil; selectedPatient = nil; patientLabs = []; patientLabPage = nil
        patientLabsLoading = false; patientLabsError = nil
        generation = UUID(); selectionGeneration = UUID()
        facility = nil; identity = nil
        workspace = nil; chart = nil; contextChart = nil; selectedAppointmentID = nil
        selectedTestID = nil; draft = DoctorConsultationDraft(); instructions = ""
        historyQuery = ""; filterDates = false; day = Date()
        loading = false; loadingChart = false; saving = false; error = nil; confirmation = nil
        startKey = UUID(); saveKey = UUID(); orderKey = UUID()
        draftInitialized = false; draftNoteID = nil; draftNoteVersion = nil
        savedDraft = nil; saveState = .idle; conflictNote = nil; lastFailure = nil
        clearPrescription(); statusFilter = "pending"; planningRevision = nil
    }

    /// silent: sincronización en segundo plano; no bloquea la pantalla ni borra la agenda si falla.
    func refresh(silent: Bool = false) async {
        guard let facility, !loading, !saving else { return }
        let scope = generation
        let calendar = DoctorClinicalRules.calendar
        let start = calendar.startOfDay(for: day)
        // Desde 2 días antes (consultas en atención o finalizadas tarde) hasta los 14 siguientes; máximo del servidor: 32.
        guard let from = calendar.date(byAdding: .day, value: -DoctorClinicalRules.agendaLookbackDays, to: start),
              let to = calendar.date(byAdding: .day, value: Self.agendaDays, to: start) else { return }
        if !silent { loading = true; error = nil }
        defer { if !silent && generation == scope { loading = false } }
        do {
            let value = try await repository.workspace(facility: facility, from: from, to: to)
            guard scope == generation, !Task.isCancelled else { return }
            workspace = value
            if !silent { await refreshAlerts() }
            if let selectedAppointmentID, !value.appointments.contains(where: { $0.id == selectedAppointmentID }) {
                let patient = selectedPatient; select(nil); selectedPatient = patient
            }
        } catch {
            guard scope == generation, !silent else { return }
            workspace = nil; chart = nil; contextChart = nil
            self.error = Self.describe(error)
        }
    }

    /// Sincronización segura sin Realtime en la app: lee el contador planning_revision (una fila) y solo vuelve a pedir
    /// la agenda si cambió. No interrumpe una consulta abierta ni un guardado.
    func syncAgendaIfChanged() async {
        guard facility != nil, !loading, !saving, !loadingChart, selectedAppointmentID == nil else { return }
        let scope = generation
        guard let revision = try? await repository.planningRevision(), scope == generation else {
            await refresh(silent: true); return
        }
        if planningRevision != revision { planningRevision = revision; await refresh(silent: true) }
    }

    func refreshAlerts(more: Bool = false) async {
        guard facility != nil, !loadingAlerts, !more || alertsHaveMore else { return }
        let scope = generation
        loadingAlerts = true
        defer { loadingAlerts = false }
        do {
            let page = try await repository.alerts(offset: more ? alerts.count : 0)
            guard generation == scope, !Task.isCancelled else { return }
            alerts = more ? alerts + page.items : page.items
            unreadAlerts = page.unread; alertsHaveMore = page.has_more; alertsError = nil
            if !more { await scheduleReminders(page.upcoming, scope: scope) }
        } catch { if generation == scope { alertsError = "No se pudieron actualizar los avisos. Reintenta." } }
    }

    func enableReminders() async {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            notificationMessage = allowed ? "Recordatorios activados para las citas sincronizadas." : "Puedes permitir notificaciones desde Ajustes del iPhone."
            await refreshAlerts()
        } catch { notificationMessage = "No se pudo solicitar permiso para las notificaciones." }
    }

    private func scheduleReminders(_ appointments: [DoctorAlerts.Upcoming], scope: UUID) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard generation == scope, settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let pending = await center.pendingNotificationRequests()
        guard generation == scope else { return }
        let identifiers = Set(appointments.map { notificationPrefix + $0.id.uuidString + "." + $0.starts_at })
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix(notificationPrefix) && !identifiers.contains($0.identifier) }.map(\.identifier))
        let scheduled = Set(pending.map(\.identifier))
        for appointment in appointments {
            guard generation == scope, let start = DoctorDate.parse(appointment.starts_at) else { continue }
            let identifier = notificationPrefix + appointment.id.uuidString + "." + appointment.starts_at
            let delay = start.addingTimeInterval(-15 * 60).timeIntervalSinceNow
            guard delay > 1, !scheduled.contains(identifier) else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Tu consulta comienza en 15 minutos"
            content.body = "Abre Hospital Universitario para revisar tu agenda."
            content.sound = .default
            do {
                try await center.add(UNNotificationRequest(identifier: identifier,
                    content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)))
                if generation != scope { center.removePendingNotificationRequests(withIdentifiers: [identifier]) }
            } catch { if generation == scope { notificationMessage = "No se pudo programar algún recordatorio. Actualiza los avisos." } }
        }
    }

    func select(_ appointment: UUID?) {
        guard !saving else { return }
        selectedPatient = nil; patientLabs = []; patientLabPage = nil; patientLabsError = nil; patientStays = nil; patientStaysError = nil; patientLabsLoading = false
        if pendingLabs == nil { selectedLabIDs = [] }
        selectionGeneration = UUID()
        selectedAppointmentID = appointment; chart = nil; contextChart = nil
        draft = DoctorConsultationDraft(); instructions = ""; selectedTestID = nil
        error = nil; confirmation = nil; loadingChart = false
        startKey = UUID(); saveKey = UUID(); orderKey = UUID()
        draftInitialized = false; draftNoteID = nil; draftNoteVersion = nil
        savedDraft = nil; saveState = .idle; conflictNote = nil; lastFailure = nil
        clearPrescription()
    }

    /// silent: actualización periódica del expediente abierto; no bloquea la pantalla ni borra lo mostrado si falla.
    func loadChart(filtered: Bool = false, silent: Bool = false) async {
        guard let patient = selectedPatient?.id ?? selectedAppointment?.patient_id else { return }
        let scope = generation
        let selection = selectionGeneration
        guard !filtered || !filterDates || historyFrom <= historyTo else {
            error = "La fecha inicial no puede ser posterior a la final."; return
        }
        if silent && (loadingChart || saving) { return }
        if !silent { loadingChart = true; error = nil }
        defer { if !silent && scope == generation && selection == selectionGeneration { loadingChart = false } }
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
                    let stored = Self.draft(from: note)
                    draft = stored; savedDraft = stored
                    // Los síntomas que envió el paciente se muestran aparte, de solo lectura; no se copian a la nota médica.
                    draftNoteID = note.note_id; draftNoteVersion = note.note_version; draftInitialized = true
                }
            }
        } catch {
            guard scope == generation, selection == selectionGeneration, !silent else { return }
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
    /// Última búsqueda enviada al servidor: evita repetir la misma consulta en cada pulsación.
    private(set) var lastDirectoryQuery: String?
    /// Búsqueda con espera breve (la vista cancela la anterior al escribir); no consulta si el texto no cambió.
    func searchPatients(debounce: Duration = .milliseconds(350)) async {
        let query = patientQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != lastDirectoryQuery || directoryError != nil else { return }
        do { try await Task.sleep(for: debounce) } catch { return }
        guard !Task.isCancelled, query == patientQuery.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        await loadPatients()
    }
    func loadPatients(more: Bool = false) async {
        guard facility != nil, !saving, !more || (!directoryLoading && directoryPage?.has_more == true) else { return }
        let query = patientQuery.trimmingCharacters(in:.whitespacesAndNewlines)
        guard query.count<=120 else { directoryError="La búsqueda admite hasta 120 caracteres."; return }
        if !more { lastDirectoryQuery = query }
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
        if !more {
            patientStays=nil; patientStaysError=nil
            do {
                let stays=try await repository.patientHospitalizations(patient:patient)
                if scope==generation && selection==selectionGeneration { patientStays=stays }
            } catch {
                let detail=String(describing:error)
                if scope==generation && selection==selectionGeneration {
                    patientStaysError=detail.contains("PGRST202") || detail.contains("404") || detail.contains("patient_hospitalizations") ? "Consulta de hospitalizaciones pendiente de migración en el servidor." : Self.describe(error)
                }
            }
        }
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

    func loadTransports() async {
        guard facility != nil, !saving else { return }
        let scope = generation, request = UUID(); transportsGeneration = request
        transportsLoading = true; transportsError = nil
        defer { if scope == generation && request == transportsGeneration { transportsLoading = false } }
        do {
            let board = try await repository.transports()
            guard scope == generation, request == transportsGeneration, !Task.isCancelled else { return }
            transportBoard = board
        } catch {
            if scope == generation && request == transportsGeneration { transportsError = Self.describe(error) }
        }
    }
    /// Contacto y teléfono se proponen desde el paciente elegido; el médico puede corregirlos.
    func prefillTransportContact() {
        if transportContact.isEmpty, let name = selectedPatient?.full_name ?? selectedAppointment?.patient_name { transportContact = name }
        if transportPhone.isEmpty, let phone = selectedPatient?.phone ?? selectedAppointment?.phone { transportPhone = phone }
    }
    var canRequestTransport: Bool {
        if pendingTransport != nil { return true }
        func filled(_ value: String, _ limit: Int) -> Bool { let text = value.trimmingCharacters(in: .whitespacesAndNewlines); return !text.isEmpty && text.count <= limit }
        return (selectedPatient?.id ?? selectedAppointment?.patient_id) != nil && ["normal", "urgente"].contains(transportPriority) &&
            filled(transportContact, 200) && filled(transportPhone, 50) && filled(transportOrigin, 1000) &&
            filled(transportDestination, 1000) && filled(transportReason, 4000)
    }
    func requestTransport() async {
        guard canRequestTransport, !saving, !loadingChart else { return }
        if pendingTransport == nil, let patient = selectedPatient?.id ?? selectedAppointment?.patient_id {
            let clean = { (value: String) in value.trimmingCharacters(in: .whitespacesAndNewlines) }
            pendingTransport = DoctorTransportInput(patient: patient, patientName: selectedPatient?.full_name ?? selectedAppointment?.patient_name ?? "",
                contact: clean(transportContact), phone: clean(transportPhone), origin: clean(transportOrigin),
                destination: clean(transportDestination), reason: clean(transportReason), priority: transportPriority, key: UUID())
        }
        guard let input = pendingTransport else { return }
        let scope = generation; saving = true; transportsError = nil; confirmation = nil
        do {
            try await repository.requestTransport(input)
            guard scope == generation else { return }
            resetTransportForm()
            saving = false; confirmation = "Solicitud de ambulancia enviada. Administración la autoriza y asigna la unidad."
            await loadTransports()
        } catch {
            guard scope == generation else { return }
            saving = false; transportsError = Self.describe(error)
            // Igual que en ingresos: un rechazo conocido descarta el envío; un fallo de red conserva datos y clave para reintentar sin duplicar.
            if let failure = error as? BackendFailure, [400,401,403,409,422].contains(failure.status) { pendingTransport = nil }
            if error is HospitalError { pendingTransport = nil }
        }
    }
    func resetTransportForm() {
        transportForm = false; pendingTransport = nil; transportPriority = "normal"
        transportContact = ""; transportPhone = ""; transportOrigin = ""; transportDestination = ""; transportReason = ""
    }

    func startConsultation() async {
        guard let appointment = selectedAppointment, appointment.encounter_id == nil else { return }
        let key = startKey
        let scope = generation
        await mutate(success: "Consulta iniciada.") {
            try await self.repository.start(appointment: appointment.id, requestKey: key)
            if self.generation == scope { self.startKey = UUID(); self.draftInitialized = false }
        }
        if let message = error, let hint = DoctorClinicalRules.startError(message) { error = hint }
    }

    static func draft(from note: DoctorConsultation) -> DoctorConsultationDraft {
        DoctorConsultationDraft(subjective: note.subjective ?? "", objective: note.objective ?? "", assessment: note.assessment ?? "",
            plan: note.plan ?? "", diagnosis_code: note.diagnosis_code ?? "", vitals: note.vitals ?? [:])
    }

    /// Guarda avances con doctor_native_save. Ante un error la información escrita permanece en pantalla;
    /// ante un conflicto de versión se recupera la versión real antes de permitir sobrescribirla.
    @discardableResult
    func saveConsultation() async -> Bool {
        guard let encounter = activeConsultation, canEditConsultation, conflictNote == nil else { return false }
        guard draft.canSave else { error = "Cada sección admite hasta 10 000 caracteres y el código hasta 50."; saveState = .failed("Revisa la longitud de los campos."); return false }
        if let issue = vitalIssues.values.first { error = "Revisa los datos físicos: \(issue)"; saveState = .failed("Revisa los datos físicos."); return false }
        let values = draft
        let key = saveKey
        let noteID = draftNoteID, version = draftNoteVersion, scope = generation, selection = selectionGeneration
        saveState = .saving
        let saved = await mutate(success: "Consulta guardada correctamente.") {
            try await self.repository.save(encounter: encounter.id, note: noteID,
                version: version, draft: values, requestKey: key)
            if self.generation == scope { self.saveKey = UUID(); self.draftInitialized = false }
        }
        guard generation == scope, selectionGeneration == selection else { return false }
        // Guardado confirmado por el servidor; si la recarga falla se informa sin presentarlo como error de guardado.
        if saved { saveState = .saved; return error == nil }
        if let failure = lastFailure as? HospitalError, case .conflict = failure { await loadServerVersion(scope: scope, selection: selection) }
        saveState = .failed(error ?? "No se pudo guardar.")
        return false
    }

    private func loadServerVersion(scope: UUID, selection: UUID) async {
        guard let patient = selectedPatient?.id ?? selectedAppointment?.patient_id else { return }
        do {
            let value = try await repository.chart(patient: patient, from: nil, to: nil, query: "")
            guard generation == scope, selectionGeneration == selection else { return }
            contextChart = value; chart = value
            conflictNote = activeConsultation
            error = "Otra sesión guardó esta consulta. Revisa la versión guardada antes de sobrescribirla."
        } catch { if generation == scope { self.error = Self.describe(error) } }
    }

    /// keepMine: guarda lo escrito sobre la versión recién recuperada. En otro caso adopta la versión del servidor.
    func resolveConflict(keepMine: Bool) async {
        guard let server = conflictNote else { return }
        conflictNote = nil; error = nil
        draftNoteID = server.note_id; draftNoteVersion = server.note_version
        savedDraft = Self.draft(from: server)
        if keepMine { await saveConsultation() } else { draft = Self.draft(from: server); saveState = .idle }
    }

    /// Requisitos de cierre: síntomas, diagnóstico y observaciones, datos físicos válidos y ninguna receta a medio preparar.
    var finishBlockers: [String] {
        var values = draft.missingSections.map { "Completa: \($0)" }
        if !vitalIssues.isEmpty { values.append("Corrige los datos físicos marcados") }
        if !rxLines.isEmpty { values.append("Emite o retira los medicamentos de la receta en preparación") }
        // Exámenes elegidos pero sin confirmar el envío: finalizar los perdería sin aviso.
        if !selectedLabIDs.isEmpty || pendingLabs != nil { values.append("Confirma el envío de los exámenes seleccionados o quítalos") }
        if conflictNote != nil { values.append("Resuelve la diferencia con la versión guardada") }
        return values
    }

    static let unsavedFinishMessage = "No se ha guardado la consulta. Guarda los cambios antes de finalizar la atención."
    /// Guarda los cambios pendientes y después ejecuta doctor_native_finish con la versión recién guardada.
    @discardableResult
    func closeConsultation() async -> Bool {
        guard canEditConsultation, !saving, !loading, !loadingChart else { return false }
        guard draft.canSave, finishBlockers.isEmpty else {
            error = finishBlockers.joined(separator: ". ") + "."; return false
        }
        let scope = generation, selection = selectionGeneration
        guard await saveConsultation(), generation == scope, selectionGeneration == selection, error == nil,
              let encounter = activeConsultation, let note = encounter.note_id, let version = encounter.note_version else {
            if generation == scope && conflictNote == nil { error = Self.unsavedFinishMessage }
            return false
        }
        let finished = await mutate(success: "Consulta finalizada. La información quedó registrada en el expediente del paciente.") {
            try await self.repository.close(encounter: encounter.id, note: note,
                noteVersion: version, encounterVersion: encounter.row_version)
        }
        guard finished, generation == scope else {
            if let message = error { error = DoctorClinicalRules.finishError(message, plan: draft.plan) }
            return false
        }
        // Regreso a la agenda conservando el aviso de finalización.
        let message = confirmation
        select(nil); confirmation = message
        return true
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
        guard notification.read_at == nil, !saving else { return }
        let scope = generation
        do {
            try await repository.markRead(notification)
            guard generation == scope else { return }
            await refreshAlerts()
        } catch { if generation == scope { alertsError = "No se pudo marcar el aviso como leído. Reintenta." } }
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

    /// Devuelve true si la operación del servidor se confirmó (aunque falle la recarga posterior, que deja `error`).
    @discardableResult
    private func mutate(success: String, reloadChart: Bool = true, operation: () async throws -> Void) async -> Bool {
        guard !saving, !loading, !loadingChart, facility != nil else { return false }
        let scope = generation
        saving = true; error = nil; confirmation = nil; lastFailure = nil
        do {
            try await operation()
            guard scope == generation else { return false }
            confirmation = success
            saving = false
            await refresh()
            if reloadChart { await loadChart() }
            return true
        } catch {
            guard scope == generation else { return false }
            saving = false
            lastFailure = error
            self.error = Self.describe(error)
            return false
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
