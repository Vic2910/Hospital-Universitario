import Foundation
import Combine

struct AttentionPerson: Codable, Equatable {
    var first_name: String?
    var last_name: String?
    var birth_date: String?
    var dui: String?
    var phone: String?
    var email: String?
}
struct AttentionSpecialty: Decodable, Identifiable {
    let id: Int64
    let name: String
    let available: Bool
}
struct AttentionSymptom: Decodable, Identifiable {
    let id: Int64
    let name: String
}
struct AttentionContext: Decodable {
    let person: AttentionPerson
    let specialties: [AttentionSpecialty]
    let symptoms: [AttentionSymptom]
}
struct AttentionRequest: Decodable, Identifiable {
    let id: UUID
    let created_at: String
    let status: String
    let specialty_name: String
    let reason: String
    let preferred_period: String
    let symptoms: [String]
    let other_symptoms: String?
    let appointment_id: UUID?
    var statusLabel: String {
        ["pendiente": "Pendiente", "en_revision": "En revisión", "agendada": "Cita programada",
         "rechazada": "Rechazada", "cancelada": "Cancelada"][status] ?? "Estado no disponible"
    }
    var periodLabel: String { ["manana": "Mañana", "tarde": "Tarde", "indiferente": "Indiferente"][preferred_period] ?? "No disponible" }
}
/// Una sola solicitud activa por paciente (espejo de HospitalCore.attentionBlocker en web-preview).
/// Mientras una solicitud esté pendiente o en revisión, o exista una cita programada, no se envía otra.
enum AttentionRules {
    static let openStates: Set<String> = ["pendiente", "en_revision"]
    static func blocker(requests: [AttentionRequest], scheduled: ProximaCita?) -> String? {
        if let open = requests.first(where: { openStates.contains($0.status) }) {
            let date = DoctorDate.parse(open.created_at).map { $0.formatted(.dateTime.locale(Locale(identifier: "es_SV")).day().month(.wide).year()) } ?? "recientemente"
            return "Ya enviaste una solicitud el \(date) y recepción la está revisando. Podrás enviar otra cuando la programe o la rechace."
        }
        if let scheduled, ["programada", "confirmada", "en_atencion", "scheduled", "confirmed", "in_progress"].contains(scheduled.status) {
            let date = DoctorDate.parse(scheduled.starts_at).map {
                $0.formatted(Date.FormatStyle(date: .long, time: .shortened, locale: Locale(identifier: "es_SV"), calendar: DoctorClinicalRules.calendar, timeZone: DoctorClinicalRules.timeZone))
            } ?? "próximamente"
            return "Ya tienes una cita programada para el \(date). Si necesitas cambiarla, comunícate con recepción."
        }
        return nil
    }
}

struct AttentionSubmission {
    let key: UUID
    let specialty: Int64
    let period: String
    let reason: String
    let symptoms: [Int64]
    let other: String?
    let missing: [String: String]
    var parameters: [String: Any] {
        ["p_key": key.uuidString, "p_specialty": specialty, "p_period": period, "p_reason": reason,
         "p_symptoms": symptoms, "p_other": other as Any? ?? NSNull(), "p_missing": missing]
    }
}
@MainActor protocol AttentionServing {
    func context() async throws -> AttentionContext
    func requests() async throws -> [AttentionRequest]
    func submit(_ value: AttentionSubmission) async throws -> UUID
}
@MainActor final class AttentionRepository: AttentionServing {
    private let api: HospitalAPI
    init(api: HospitalAPI) { self.api = api }
    func context() async throws -> AttentionContext { try await api.attentionRPC("my_attention_context") }
    func requests() async throws -> [AttentionRequest] { try await api.attentionRPC("my_attention_requests") }
    func submit(_ value: AttentionSubmission) async throws -> UUID {
        try await api.attentionRPC("submit_my_attention_request", parameters: value.parameters)
    }
}

@MainActor final class PatientAttentionModel: ObservableObject {
    @Published private(set) var context: AttentionContext?
    @Published private(set) var requests: [AttentionRequest] = []
    @Published private(set) var loading = false
    @Published private(set) var saving = false
    @Published private(set) var error: String?
    @Published private(set) var confirmation: String?
    @Published var selectedSymptoms: Set<Int64> = []
    @Published var specialty: Int64?
    @Published var preferredPeriod = "indiferente"
    @Published var reason = ""
    @Published var otherSymptoms = ""
    @Published var missing: [String: String] = [:]
    /// Próxima cita autorizada (patientDashboard); la asigna HospitalStore antes de abrir el formulario.
    @Published var scheduledAppointment: ProximaCita?
    var submissionBlocker: String? { AttentionRules.blocker(requests: requests, scheduled: scheduledAppointment) }
    private let repository: any AttentionServing
    private var owner: UUID?
    private var generation = UUID()
    private var requestKey = UUID()

    init(repository: any AttentionServing) { self.repository = repository }
    func configure(owner: UUID) {
        guard self.owner != owner else { return }
        clear(); self.owner = owner
    }
    func clear() {
        generation = UUID(); owner = nil; requestKey = UUID()
        context = nil; requests = []; loading = false; saving = false; error = nil; confirmation = nil
        selectedSymptoms = []; specialty = nil; preferredPeriod = "indiferente"
        reason = ""; otherSymptoms = ""; missing = [:]; scheduledAppointment = nil
    }
    func isMissing(_ value: String?) -> Bool { value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false }
    var needsOtherDescription: Bool {
        context?.symptoms.contains { $0.name == "Otro" && selectedSymptoms.contains($0.id) } == true
    }
    var personalValues: [String: String] {
        guard let person = context?.person else { return [:] }
        let existing = ["first_name": person.first_name, "last_name": person.last_name, "dui": person.dui,
                        "birth_date": person.birth_date, "phone": person.phone]
        return existing.mapValues { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }.merging(missing) { original, completion in
            original.isEmpty ? completion.trimmingCharacters(in: .whitespacesAndNewlines) : original
        }
    }
    var validationError: String? {
        guard let context else { return "Espera a que se carguen tus datos." }
        let person = personalValues
        for key in ["first_name", "last_name"] {
            if (person[key] ?? "").isEmpty || (person[key]?.count ?? 0)>100 { return "Completa tus nombres y apellidos (máximo 100 caracteres)." }
        }
        if person["dui"]?.range(of: "^[0-9]{8}-[0-9]$", options: .regularExpression) == nil { return "Completa tu DUI con formato 00000000-0." }
        if person["phone"]?.range(of: "^[0-9]{4}-[0-9]{4}$", options: .regularExpression) == nil { return "Completa tu teléfono con formato 0000-0000." }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let text = person["birth_date"], text.count == 10, let date = formatter.date(from: text),
              formatter.string(from: date) == text, date <= Date(),
              let oldest = Calendar.current.date(byAdding: .year, value: -120, to: Date()), date >= oldest else { return "Introduce una fecha de nacimiento válida (AAAA-MM-DD)." }
        if isMissing(context.person.email) { return "Tu cuenta no publica un correo. Contacta al hospital para completar el acceso." }
        guard let specialty, context.specialties.contains(where: { $0.id == specialty && $0.available }) else { return "Selecciona una especialidad con médico activo asignado." }
        if selectedSymptoms.isEmpty || !selectedSymptoms.isSubset(of: Set(context.symptoms.map(\.id))) { return "Selecciona al menos un síntoma del catálogo." }
        if needsOtherDescription && otherSymptoms.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Describe el otro síntoma." }
        if otherSymptoms.count>1000 { return "La descripción admite hasta 1000 caracteres." }
        if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reason.count>2000 { return "Escribe el motivo de solicitud (máximo 2000 caracteres)." }
        if !["manana", "tarde", "indiferente"].contains(preferredPeriod) { return "Selecciona una preferencia de horario válida." }
        return nil
    }
    var canSubmit: Bool { owner != nil && !loading && !saving && submissionBlocker == nil && validationError == nil }
    func load() async {
        guard owner != nil, !loading, !saving else { return }
        let scope = generation; loading = true; error = nil
        defer { if scope == generation { loading = false } }
        do {
            let value = try await repository.context()
            let rows = try await repository.requests()
            guard scope == generation, !Task.isCancelled else { return }
            context = value; requests = rows
            if let specialty, !value.specialties.contains(where: { $0.id == specialty && $0.available }) { self.specialty = nil }
            selectedSymptoms.formIntersection(Set(value.symptoms.map(\.id)))
        } catch {
            guard scope == generation else { return }
            context = nil; requests = []; self.error = Self.describe(error)
        }
    }
    func submit() async {
        guard canSubmit, let specialty, let person = context?.person else { return }
        let scope = generation; saving = true; error = nil; confirmation = nil
        defer { if scope == generation { saving = false } }
        let existing = ["first_name": person.first_name, "last_name": person.last_name, "dui": person.dui, "birth_date": person.birth_date, "phone": person.phone]
        let completions = personalValues.filter { isMissing(existing[$0.key] ?? nil) }
        let submission = AttentionSubmission(key: requestKey, specialty: specialty, period: preferredPeriod,
            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines), symptoms: selectedSymptoms.sorted(),
            other: needsOtherDescription ? otherSymptoms.trimmingCharacters(in: .whitespacesAndNewlines) : nil, missing: completions)
        do {
            _ = try await repository.submit(submission)
            guard scope == generation else { return }
            completeSubmission()
        } catch {
            guard scope == generation else { return }
            // A lost response may hide a successful commit. Reconcile using the same key.
            if let rows = try? await repository.requests(), scope == generation, rows.contains(where: { $0.id == requestKey }) {
                requests = rows; completeSubmission()
            } else if scope == generation { self.error = "\(Self.describe(error)) Puedes reintentar: se conserva el identificador para evitar duplicados." }
        }
        guard scope == generation else { return }
        if confirmation != nil {
            do {
                let rows = try await repository.requests()
                let value = try await repository.context()
                guard scope == generation else { return }
                requests = rows; context = value; missing = [:]
            } catch { if scope == generation { self.error = "Solicitud enviada. No se pudo actualizar el seguimiento; pulsa Actualizar." } }
        }
    }
    private func completeSubmission() {
        requestKey = UUID(); reason = ""; selectedSymptoms = []; otherSymptoms = ""
        confirmation = "Solicitud enviada a recepción. No se ha creado un expediente ni reservado una cita."
    }
    private static func describe(_ error: Error) -> String {
        if error is URLError { return "No se pudo conectar con el hospital. Revisa tu conexión." }
        if let known = error as? HospitalError { return known.localizedDescription }
        if let known = error as? BackendFailure { return known.localizedDescription }
        return "No se pudo completar la solicitud. Actualiza tus datos e inténtalo de nuevo."
    }
}
