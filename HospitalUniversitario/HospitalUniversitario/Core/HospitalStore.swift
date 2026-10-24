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
    @Published private(set) var mfaFactors: [MFAFactor] = []
    @Published var selectedFactor: UUID?
    @Published var screenMessage: String?
    @Published private(set) var roomsMore = false
    @Published private(set) var shiftsMore = false
    private var roomsCursor: ResourceCursor?
    private var shiftsCursor: ResourceCursor?
    private var api: HospitalAPI?
    private var restored = false

    init() {
        do { api = HospitalAPI(core: try SharedCore()); catalog = try ScreenCatalog.load() }
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
        guard (try? RefreshTokenStore.read()) != nil else { return }
        busy = true
        defer { busy = false }
        do { try await resolveAccess() }
        catch { api?.clearLocal(); reset(); message = error.localizedDescription }
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
        let factors = try await api.factors().filter { $0.status == "verified" }
        if access.aal != "aal2" && !factors.isEmpty {
            let totp = factors.filter { $0.factor_type == "totp" }
            guard !totp.isEmpty else { throw HospitalError.message("Esta cuenta requiere un segundo factor no compatible. Contacta al administrador.") }
            mfaFactors = totp
            selectedFactor = totp.first?.id
            return
        }
        mfaFactors = []; selectedFactor = nil
        self.access = access
        self.roles = roles
        selectedRole = roles.count == 1 ? roles[0] : nil
    }

    func verify(code: String) async {
        guard !busy, let api, let selectedFactor else { return }
        busy = true; message = nil
        defer { busy = false }
        do { try await api.verifyTOTP(factor: selectedFactor, code: code); try await resolveAccess() }
        catch { message = "No se pudo verificar el código. Revisa tu autenticador e inténtalo de nuevo." }
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
                api.clearLocal(); reset(); throw HospitalError.message("El acceso cambió. Inicia sesión de nuevo.")
            }
            access = fresh; roles = available
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
            case "profile": profile = try await api.rpc("my_profile")
            default: break
            }
        } catch {
            rooms = []; shifts = []; tickets = []; queueStatuses = []; summary = nil; overview = nil
            roomsMore = false; shiftsMore = false
            if let failure = error as? BackendFailure, failure.status == 401 { api.clearLocal(); reset() }
            message = error.localizedDescription
        }
    }
    func period(_ value: String) -> String { api?.core.period(value) ?? value }
    func signOut() async {
        guard !busy else { return }
        busy = true
        let warning = await api?.signOut()
        reset()
        message = warning
        busy = false
    }
    func switchRole() {
        selectedRole = nil
        rooms = []; shifts = []; tickets = []; message = nil
        roomsCursor = nil; shiftsCursor = nil; roomsMore = false; shiftsMore = false
        screenID = "home"; summary = nil; profile = nil; overview = nil; queueStatuses = []; screenMessage = nil
    }
    private func reset() {
        access = nil; roles = []; selectedRole = nil
        rooms = []; shifts = []; tickets = []; roomsCursor = nil; shiftsCursor = nil
        roomsMore = false; shiftsMore = false
        screenID = "home"; summary = nil; profile = nil; overview = nil; queueStatuses = []
        mfaFactors = []; selectedFactor = nil; screenMessage = nil
    }
}
