import SwiftUI

@MainActor
final class HospitalStore: ObservableObject {
    @Published private(set) var access: HospitalAccess?
    @Published private(set) var roles: [String] = []
    @Published var selectedRole: String?
    @Published private(set) var rooms: [Room] = []
    @Published private(set) var shifts: [StaffShift] = []
    @Published private(set) var busy = false
    @Published var message: String?
    @Published var screenID = "home"
    @Published private(set) var catalog: [String: [HospitalScreen]] = [:]
    @Published private(set) var summary: ActivitySummary?
    @Published private(set) var nextAppointment: ProximaCita?
    @Published private(set) var profile: UserProfile?
    @Published private(set) var overview: HospitalOverview?
    @Published var screenMessage: String?
    @Published private(set) var roomsMore = false
    @Published private(set) var shiftsMore = false
    @Published private(set) var doctor: DoctorViewModel?
    @Published private(set) var patientLaboratory: MobileModuleViewModel?
    @Published private(set) var modules: MobileModuleViewModel?
    private var roomsCursor: ResourceCursor?
    private var shiftsCursor: ResourceCursor?
    private var api: HospitalAPI?
    private var restored = false

    init() {
        do {
            let api = HospitalAPI(core: try SharedCore())
            self.api = api
            doctor = DoctorViewModel(repository: DoctorRepository(api: api))
            modules = MobileModuleViewModel(repository: MobileModuleRepository(api: api))
            patientLaboratory = MobileModuleViewModel(repository: MobileModuleRepository(api: api))
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
        orderedShifts.first { $0.status != "cancelado" && $0.status != "cancelled" && (api?.core.interval($0.period)?.end ?? .distantPast) > Date() }
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
            throw HospitalError.message("Tu cuenta no tiene un rol activo permitido en esta app.")
        }
        self.access = access
        self.roles = roles
        selectedRole = roles.count == 1 ? roles[0] : nil
    }

    func register(email: String, password: String, values: [String: Any]) async {
        guard !busy, let api else { return }
        busy = true; message = nil
        defer { busy = false }
        do {
            if access == nil {
                let metadata = ["first_name": values["first_name"] as? String ?? "", "last_name": values["last_name"] as? String ?? "",
                    "birth_date": values["birth_date"] as? String ?? "", "phone": values["phone"] as? String ?? "", "city": values["city"] as? String ?? "",
                    "dui": values["dui"] as? String ?? ""]
                guard try await api.signUp(email: email, password: password, metadata: metadata) else {
                    message = "Cuenta creada. El servidor todavía exige confirmar el correo; el hospital debe desactivar ese requisito en Auth. No vuelvas a crear la cuenta."
                    return
                }
            }
            try await resolveAccess()
        } catch {
            // Recover the authenticated account after a partially completed signup.
            try? await resolveAccess()
            message = "No se pudo consultar tu acceso: \(error.localizedDescription) Si ya creaste la cuenta, inicia sesión; no vuelvas a registrarte."
        }
    }

    func refreshRegistration() async {
        guard !busy else { return }
        busy = true; message = nil
        defer { busy = false }
        do { try await resolveAccess() }
        catch { message = error.localizedDescription }
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
            nextAppointment = nil
            if let facility = fresh.roles.first(where: { $0.code == role })?.context_id, let profile = fresh.profile {
                modules?.configure(role: role, facility: facility, profile: profile.id, patient: fresh.patient_id)
                patientLaboratory?.configure(role: role, facility: facility, profile: profile.id, patient: fresh.patient_id)
            }
            if role == "patient" && ["request", "schedule", "health"].contains(screenID) {
                await modules?.load("request"); return
            }
            if (role == "patient" && ["appointments", "request", "chart", "history", "prescriptions", "laboratory", "notifications"].contains(screenID)) || screenID == "notifications" {
                await modules?.load(screenID, more: more)
                if role == "patient" && screenID == "chart" && modules?.page != nil { await patientLaboratory?.load("laboratory") }
                return
            }
            if role == "doctor", let identity = fresh.staff_id,
               let facility = fresh.roles.first(where: { $0.code == "doctor" })?.context_id,
               ["home", "patients", "consultation", "chart", "laboratory", "notifications", "prescriptions"].contains(screenID) {
                doctor?.configure(facility: facility, identity: identity)
                if screenID == "home" { doctor?.day = Date() }
                await doctor?.refresh()
                if screenID == "prescriptions" { await modules?.load("prescriptions", more: more) }
                return
            }
            if profile == nil { profile = try await api.operation("profile") }
            let facility = fresh.roles.first(where: { $0.code == role })?.context_id
            switch screenID {
            case "home":
                summary = nil
                if role == "patient" {
                    let dashboard: PatientDashboardData = try await api.operation("patientDashboard")
                    nextAppointment = dashboard.next_appointment
                }
            case "rooms":
                if !more { rooms = []; roomsCursor = nil; roomsMore = false }
                let page = try await api.rooms(cursor: more ? roomsCursor : nil)
                rooms = more ? rooms + page.data : page.data; roomsCursor = page.next_cursor; roomsMore = page.has_more
            case "turns":
                if !more { shifts = []; shiftsCursor = nil; shiftsMore = false }
                if role == "doctor", let owner = fresh.staff_id {
                    let page = try await api.shifts(owner: owner, cursor: more ? shiftsCursor : nil)
                    shifts = more ? shifts + page.data : page.data
                    shiftsCursor = page.next_cursor; shiftsMore = page.has_more
                } else { screenMessage = "Hospital Móviles no publica una fila numerada. Consulta Mis citas." }

            case "information":
                overview = nil
                if let facility { overview = try await api.operation("overview", parameters: ["p_facility": facility.uuidString]) }
            case "profile":
                profile = try await api.operation("profile")
            default: break
            }
        } catch {
            if role == "doctor" { doctor?.clear() }
            modules?.clear(); patientLaboratory?.clear()
            rooms = []; shifts = []; summary = nil; overview = nil
            nextAppointment = nil
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
        modules?.clear(); patientLaboratory?.clear()
        selectedRole = nil
        nextAppointment = nil
        rooms = []; shifts = []; message = nil
        roomsCursor = nil; shiftsCursor = nil; roomsMore = false; shiftsMore = false
        screenID = "home"; summary = nil; profile = nil; overview = nil; screenMessage = nil
    }
    private func reset() {
        doctor?.clear()
        modules?.clear(); patientLaboratory?.clear()
        access = nil; roles = []; selectedRole = nil
        nextAppointment = nil
        rooms = []; shifts = []; roomsCursor = nil; shiftsCursor = nil
        roomsMore = false; shiftsMore = false
        screenID = "home"; summary = nil; profile = nil; overview = nil
        screenMessage = nil
    }
}
