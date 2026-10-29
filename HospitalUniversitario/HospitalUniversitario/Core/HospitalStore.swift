import SwiftUI

@MainActor
final class HospitalStore: ObservableObject {
    @Published private(set) var access: HospitalAccess?
    @Published private(set) var roles: [String] = []
    @Published var selectedRole: String?
    @Published private(set) var rooms: [Room] = []
    @Published private(set) var shifts: [StaffShift] = []
    @Published private(set) var tickets: [QueueTicket] = []
    @Published private(set) var busy = false
    @Published var message: String?
    @Published var screenID = "home"
    @Published private(set) var catalog: [String: [HospitalScreen]] = [:]
    @Published private(set) var summary: ActivitySummary?
    @Published private(set) var profile: UserProfile?
    @Published private(set) var overview: HospitalOverview?
    @Published private(set) var queueStatuses: [QueueStatus] = []
    @Published var screenMessage: String?
    @Published private(set) var roomsMore = false
    @Published private(set) var shiftsMore = false
    @Published private(set) var doctor: DoctorViewModel?
    @Published private(set) var modules: MobileModuleViewModel?
    private var roomsCursor: ResourceCursor?
    private var shiftsCursor: ResourceCursor?
    private var api: HospitalAPI?
    private var restored = false

    init() {
        do {
            let api = HospitalAPI(core: try SharedCore())
            self.api = api
            doctor = DoctorViewModel(repository: DoctorRepository(client: api.client))
            modules = MobileModuleViewModel(repository: MobileModuleRepository(client: api.client, projectURL: api.core.configuration.url))
            catalog = try ScreenCatalog.load()
        }
        catch { message = error.localizedDescription }
    }
    var name: String { access?.profile?.preferred_name ?? profile?.fullName ?? "Bienvenido" }
    var screens: [HospitalScreen] { catalog[selectedRole ?? ""] ?? [] }
    var orderedShifts: [StaffShift] {
        shifts.sorted { (api?.core.interval($0.period)?.start ?? .distantFuture) < (api?.core.interval($1.period)?.start ?? .distantFuture) }
    }
    var nextShift: StaffShift? {
        orderedShifts.first { $0.status != "cancelled" && (api?.core.interval($0.period)?.end ?? .distantPast) > Date() }
    }

    func restore() async {
        guard !restored else { return }
        restored = true
        guard api?.hasStoredSession == true else { return }
        busy = true
        defer { busy = false }
        do { try await resolveAccess() }
        catch { await api?.clearLocal(); reset(); message = error.localizedDescription }
    }
    func signIn(email: String, password: String) async {
        guard !busy, let api else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            try await api.signIn(email: email, password: password)
            try await resolveAccess()
        } catch {
            _ = await api.signOut(); reset()
            message = error.localizedDescription
        }
    }
    private func resolveAccess() async throws {
        guard let api else { throw HospitalError.message("No se pudo cargar la configuración.") }
        let (access, roles) = try await api.access()
        guard !roles.isEmpty else {
            throw HospitalError.message("Tu cuenta debe estar activa y vinculada a un Médico o Paciente con el rol correspondiente.")
        }
        self.access = access
        self.roles = roles
        selectedRole = roles.count == 1 ? roles[0] : nil
    }


    func selectRole(_ role: String) {
        guard roles.contains(role), !busy else { return }
        selectedRole = role; screenID = "home"
    }

    func refreshScreen(more: Bool = false) async {
        guard !busy, let api, let role = selectedRole else { return }
        busy = true; message = nil; screenMessage = nil
        defer { busy = false }
        do {
            let (fresh, available) = try await api.access()
            guard available.contains(role) else {
                await api.clearLocal(); reset(); throw HospitalError.message("El acceso cambió. Inicia sesión de nuevo.")
            }
            access = fresh; roles = available
            if let facility = fresh.roles.first(where: { $0.code == role })?.facility_id, let profile = fresh.profile {
                modules?.configure(role: role, facility: facility, profile: profile.id, patient: fresh.patient_id)
            }
            if (role == "patient" && ["appointments", "request", "chart", "history", "prescriptions", "laboratory", "notifications"].contains(screenID)) || screenID == "notifications" {
                await modules?.load(screenID, more: more)
                return
            }
            if role == "doctor", let identity = fresh.staff_id,
               let facility = fresh.roles.first(where: { $0.code == "doctor" })?.facility_id,
               ["home", "patients", "appointments", "consultation", "chart", "laboratory", "notifications", "prescriptions"].contains(screenID) {
                doctor?.configure(facility: facility, identity: identity)
                await doctor?.refresh()
                if screenID == "prescriptions" { await modules?.load("prescriptions", more: more) }
                return
            }
            if profile == nil { profile = try await api.rpc("my_profile") }
            let facility = fresh.roles.first(where: { $0.code == role })?.facility_id
            switch screenID {
            case "home":
                summary = nil
                guard let facility else { return }
                let from = Calendar.current.startOfDay(for: Date())
                let to = Calendar.current.date(byAdding: .day, value: role == "patient" ? 31 : 1, to: from)!
                let format = ISO8601DateFormatter()
                do {
                    summary = try await api.rpc("my_activity_summary", parameters: ["p_facility": facility.uuidString, "p_from": format.string(from: from), "p_to": format.string(from: to), "p_context": role == "doctor" ? "staff" : "patient"])
                } catch let error as BackendFailure where error.status == 403 {
                    screenMessage = "Se requiere verificación adicional o autorización para consultar el resumen."
                }
            case "rooms":
                if !more { rooms = []; roomsCursor = nil; roomsMore = false }
                let page = try await api.rooms(cursor: more ? roomsCursor : nil)
                rooms = more ? rooms + page.data : page.data; roomsCursor = page.next_cursor; roomsMore = page.has_more
            case "turns":
                if !more { shifts = []; tickets = []; queueStatuses = []; shiftsCursor = nil; shiftsMore = false }
                if role == "doctor", let owner = fresh.staff_id {
                    let page = try await api.shifts(owner: owner, cursor: more ? shiftsCursor : nil)
                    shifts = more ? shifts + page.data : page.data
                    shiftsCursor = page.next_cursor; shiftsMore = page.has_more
                } else if let owner = fresh.patient_id {
                    let page = try await api.tickets(owner: owner, cursor: more ? shiftsCursor : nil)
                    tickets = more ? tickets + page.data : page.data
                    for ticket in page.data where ["waiting", "called", "in_service"].contains(ticket.status) {
                        let status: QueueStatus = try await api.rpc("my_queue_status", parameters: ["p_ticket": ticket.id.uuidString])
                        queueStatuses.append(status)
                    }
                    shiftsCursor = page.next_cursor; shiftsMore = page.has_more
                }
            case "information":
                overview = nil
                if let facility { overview = try await api.rpc("hospital_overview", parameters: ["p_facility": facility.uuidString]) }
            case "profile":
                profile = try await api.rpc("my_profile")
                await modules?.load("profile")
            default: break
            }
        } catch {
            if role == "doctor" { doctor?.clear() }
            modules?.clear()
            rooms = []; shifts = []; tickets = []; queueStatuses = []; summary = nil; overview = nil
            roomsMore = false; shiftsMore = false
            if let failure = error as? BackendFailure, failure.status == 401 { await api.clearLocal(); reset() }
            message = error.localizedDescription
        }
    }
    func period(_ value: String) -> String { api?.core.period(value) ?? value }
    func signOut() async {
        guard !busy, doctor?.saving != true, modules?.saving != true else { return }
        busy = true
        let api = self.api
        reset()
        let warning = await api?.signOut()
        message = warning
        busy = false
    }
    func switchRole() {
        guard doctor?.saving != true, modules?.saving != true else { return }
        doctor?.clear()
        modules?.clear()
        selectedRole = nil
        rooms = []; shifts = []; tickets = []; message = nil
        roomsCursor = nil; shiftsCursor = nil; roomsMore = false; shiftsMore = false
        screenID = "home"; summary = nil; profile = nil; overview = nil; queueStatuses = []; screenMessage = nil
    }
    private func reset() {
        doctor?.clear()
        modules?.clear()
        access = nil; roles = []; selectedRole = nil
        rooms = []; shifts = []; tickets = []; roomsCursor = nil; shiftsCursor = nil
        roomsMore = false; shiftsMore = false
        screenID = "home"; summary = nil; profile = nil; overview = nil; queueStatuses = []
        screenMessage = nil
    }
}
