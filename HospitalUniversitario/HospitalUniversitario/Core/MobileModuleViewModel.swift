import Foundation
import Combine

@MainActor
final class MobileModuleViewModel: ObservableObject {
    @Published private(set) var page: MobileModulePage?
    @Published private(set) var items: [MobileItem] = []
    @Published private(set) var loading = false
    @Published private(set) var saving = false
    @Published private(set) var error: String?
    @Published private(set) var confirmation: String?
    @Published var query = ""
    @Published var filterDates = false
    @Published var from = Calendar.current.startOfDay(for: Date())
    @Published var to = Date()
    @Published var specialty: UUID?
    @Published var reason = ""
    /// Síntomas elegidos por el paciente; se añaden al motivo porque `request_appointment` no tiene parámetro de síntomas.
    @Published var symptoms: [String] = []
    @Published var preferredDay = Date()
    @Published var preferredFrom = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @Published var preferredTo = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
    @Published var phone = ""
    @Published var emergencyGiven = ""
    @Published var emergencyFamily = ""
    @Published var emergencyPhone = ""
    @Published var relationship = ""
    @Published var prescriptionLines: [PrescriptionLine] = []
    private let repository: MobileModuleRepository
    private var role = ""
    private var module = ""
    private var facility: UUID?
    private var profileID: UUID?
    private var patientID: UUID?
    private var generation = UUID()
    private var requestKey = UUID()
    private var prescriptionKey = UUID()
    private var emergencyKey = UUID()
    private var prescriptionAppointment: UUID?

    init(repository: MobileModuleRepository) { self.repository = repository }

    var canRequest: Bool {
        specialty != nil && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && reason.count <= 2000 && MobileFormatting.day(preferredDay) >= MobileFormatting.day(Date())
            && MobileFormatting.time(preferredFrom) < MobileFormatting.time(preferredTo)
    }

    func configure(role: String, facility: UUID, profile: UUID, patient: UUID?) {
        guard self.role != role || self.facility != facility || profileID != profile else { return }
        clear()
        self.role = role; self.facility = facility; profileID = profile; patientID = patient
    }

    func clear() {
        generation = UUID(); role = ""; module = ""; facility = nil; profileID = nil; patientID = nil
        page = nil; items = []; query = ""; filterDates = false
        loading = false; saving = false; error = nil; confirmation = nil
        specialty = nil; reason = ""; symptoms = []; phone = ""; emergencyGiven = ""; emergencyFamily = ""
        emergencyPhone = ""; relationship = ""; prescriptionLines = []
        requestKey = UUID(); prescriptionKey = UUID(); emergencyKey = UUID()
        prescriptionAppointment = nil
    }

    func alignPrescription(appointment: UUID?) {
        guard prescriptionAppointment != appointment else { return }
        prescriptionAppointment = appointment; prescriptionLines = []; prescriptionKey = UUID()
    }

    func load(_ module: String, more: Bool = false) async {
        guard let facility, !loading, !saving else { return }
        if self.module != module {
            self.module = module; query = ""; filterDates = false; page = nil; items = []
        }
        guard !filterDates || from <= to else { error = "El intervalo de fechas no es válido."; return }
        guard !more || page?.has_more == true else { return }
        let scope = generation
        loading = true; error = nil
        defer { if scope == generation { loading = false } }
        do {
            let result = try await repository.load(role: role, module: module, facility: facility,
                from: filterDates ? from : nil, to: filterDates ? to : nil, query: query,
                cursor: more ? page?.next_cursor : nil)
            guard scope == generation, !Task.isCancelled else { return }
            items = more ? items + result.items : result.items; page = result
            if module == "profile" {
                phone = result.phone ?? ""
                emergencyGiven = result.emergency?.given_names ?? ""
                emergencyFamily = result.emergency?.family_names ?? ""
                emergencyPhone = result.emergency?.phones.first ?? ""
                relationship = result.emergency?.relationship ?? ""
            }
        } catch {
            guard scope == generation else { return }
            if !more { page = nil; items = [] }
            self.error = DoctorViewModel.describe(error)
        }
    }

    @discardableResult
    private func mutate(_ success: String, reload: Bool = true, operation: () async throws -> Void) async -> Bool {
        guard !saving, !loading, facility != nil else { return false }
        let scope = generation
        saving = true; error = nil; confirmation = nil
        do {
            try await operation()
            guard scope == generation else { return false }
            saving = false; confirmation = success
            if reload { await load(module) }
            return scope == generation
        } catch {
            guard scope == generation else { return false }
            saving = false; self.error = DoctorViewModel.describe(error); return false
        }
    }

    func requestAppointment() async {
        guard canRequest, let facility, let patientID else { return }
        let base = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let listed = symptoms.filter { !$0.isEmpty }.joined(separator: ", ")
        let text = listed.isEmpty ? base : base + "\nSíntomas: " + listed
        let parameters: [String: DoctorJSON] = ["p_patient": .string(patientID.uuidString), "p_facility": .string(facility.uuidString),
            "p_specialty": specialty.map { .string($0.uuidString) } ?? .null,
            "p_reason": .string(text),
            "p_date": .string(MobileFormatting.day(preferredDay)), "p_from": .string(MobileFormatting.time(preferredFrom)),
            "p_to": .string(MobileFormatting.time(preferredTo)), "p_request_key": .string(requestKey.uuidString)]
        if await mutate("Solicitud enviada. Recepción confirmará la disponibilidad.", operation: {
            try await self.repository.perform("request_appointment", parameters)
        }) { requestKey = UUID(); reason = ""; symptoms = [] }
    }

    func cancel(_ item: MobileItem, reason: String) async {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, item.action == "cancel_appointment" else { return }
        await mutate("Cita cancelada.") {
            try await self.repository.perform("transition_appointment", ["p_id": .string(item.id.uuidString),
                "p_status": .string("cancelled"), "p_reason": .string(reason), "p_expected_version": .number(item.row_version)])
        }
    }

    func markRead(_ item: MobileItem) async {
        guard item.action == "mark_read" else { return }
        await mutate("Notificación marcada como leída.") {
            try await self.repository.perform("update_record", ["p_resource": .string("notifications"),
                "p_id": .string(item.id.uuidString), "p_values": .object(["read_at": .string(DoctorDate.timestamp(Date()))]),
                "p_expected_version": .number(item.row_version)])
        }
    }

    func savePhone() async {
        let value = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: "^[+]?[0-9() -]{7,25}$", options: .regularExpression) != nil else {
            error = "Introduce un teléfono válido."; return
        }
        await mutate("Teléfono actualizado.") { try await self.repository.perform("update_my_phone", ["p_value": .string(value)]) }
    }

    func saveEmergency() async {
        guard !emergencyGiven.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !emergencyFamily.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !relationship.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              emergencyPhone.range(of: "^[+]?[0-9() -]{7,25}$", options: .regularExpression) != nil else {
            error = "Completa nombre, apellido, parentesco y teléfono válidos."; return
        }
        let parameters: [String: DoctorJSON] = ["p_id": page?.emergency.map { .string($0.id.uuidString) } ?? .null,
            "p_given_names": .string(emergencyGiven), "p_family_names": .string(emergencyFamily),
            "p_phone": .string(emergencyPhone), "p_relationship": .string(relationship),
            "p_expected_version": page?.emergency.map { .number($0.row_version) } ?? .null,
            "p_request_key": .string(emergencyKey.uuidString)]
        if await mutate("Contacto de emergencia actualizado.", operation: {
            try await self.repository.perform("set_my_emergency_contact", parameters)
        }) { emergencyKey = UUID() }
    }

    func setPreference(_ item: MobilePreference, enabled: Bool) async {
        guard let profileID else { return }
        await mutate("Preferencia guardada.") {
            if let id = item.preference_id, let version = item.row_version {
                try await self.repository.perform("update_record", ["p_resource": .string("notification_preferences"),
                    "p_id": .string(id.uuidString), "p_values": .object(["enabled": .bool(enabled)]), "p_expected_version": .number(version)])
            } else {
                try await self.repository.perform("create_record", ["p_resource": .string("notification_preferences"),
                    "p_values": .object(["profile_id": .string(profileID.uuidString), "topic_id": .string(item.id.uuidString),
                        "channel": .string("in_app"), "enabled": .bool(enabled)]), "p_request_key": .string(UUID().uuidString)])
            }
        }
    }

    func issuePrescription(encounter: UUID) async {
        guard !prescriptionLines.isEmpty, prescriptionLines.count <= 30 else { return }
        do {
            let encoded = try JSONEncoder().encode(prescriptionLines)
            let values = try JSONDecoder().decode(DoctorJSON.self, from: encoded)
            if await mutate("Receta emitida.", operation: {
                try await self.repository.perform("mobile_issue_prescription", ["p_encounter": .string(encounter.uuidString),
                    "p_items": values, "p_request_key": .string(self.prescriptionKey.uuidString)])
            }) { prescriptionLines = []; prescriptionKey = UUID() }
        } catch { self.error = "No se pudo preparar la receta." }
    }

    func changePassword(_ password: String) async {
        guard password.count >= 12 else { error = "La contraseña debe tener al menos 12 caracteres."; return }
        await mutate("Contraseña actualizada.", reload: false) { try await self.repository.changePassword(password) }
    }

    func documentURL(_ id: UUID) async -> URL? {
        let scope = generation
        do {
            let url = try await repository.documentURL(id)
            return scope == generation ? url : nil
        } catch {
            if scope == generation { self.error = "No se pudo autorizar el documento. Actualiza e inténtalo de nuevo." }
            return nil
        }
    }

    func confirmShift(id: UUID, version: Int) async -> Bool {
        await mutate("Jornada confirmada.", reload: false) {
            try await self.repository.perform("confirm_shift", ["p_id": .string(id.uuidString), "p_expected_version": .number(version)])
        }
    }
}
