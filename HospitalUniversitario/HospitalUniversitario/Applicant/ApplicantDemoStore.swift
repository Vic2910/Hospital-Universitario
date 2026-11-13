import Foundation
import Combine

/// Datos personales del solicitante. En la vista de diseño son ejemplos locales.
struct ApplicantPersonalData: Equatable {
    var given: String
    var family: String
    var dui: String
    var birthDate: Date?
    var phone: String
}

struct ApplicantRequestDraft: Equatable {
    var specialty = ""
    var reason = ""
    var date = Date()
    /// Valores: "morning", "afternoon" o vacío sin elegir.
    var period = ""
}

/// Solicitud de atención. `status` y `appointmentStatus` usan los valores reales del backend
/// (pending, identity_verified, converted, rejected, cancelled; y scheduled en la cita).
struct ApplicantRequestRecord: Identifiable, Equatable {
    let id: String
    var specialty: String
    var reason: String
    var date: Date
    var period: String
    var status: String
    var appointmentStatus: String?
    var decisionReason: String?
    var createdAt: Date
}

/// Almacén de la vista de diseño del solicitante. No llama a Supabase ni crea citas:
/// la solicitud queda Pendiente y solo cambia por el avance de ejemplo.
@MainActor
final class ApplicantDemoStore: ObservableObject {
    @Published private(set) var person: ApplicantPersonalData?
    @Published private(set) var requests: [ApplicantRequestRecord] = []
    @Published var notice: String?

    let rules = ApplicantRules.shared
    private var sequence = 0

    func savePersonal(_ data: ApplicantPersonalData) -> String? {
        if let problem = rules.validatePersonal(data) { return problem }
        person = ApplicantPersonalData(
            given: data.given.trimmingCharacters(in: .whitespacesAndNewlines),
            family: data.family.trimmingCharacters(in: .whitespacesAndNewlines),
            dui: rules.formatDUI(data.dui),
            birthDate: data.birthDate,
            phone: data.phone.trimmingCharacters(in: .whitespacesAndNewlines))
        notice = "Datos de ejemplo guardados solo en esta vista."
        return nil
    }

    func submitRequest(_ draft: ApplicantRequestDraft) -> String? {
        if let problem = rules.validateRequest(draft) { return problem }
        sequence += 1
        let record = ApplicantRequestRecord(
            id: "ejemplo-\(sequence)",
            specialty: draft.specialty,
            reason: draft.reason.trimmingCharacters(in: .whitespacesAndNewlines),
            date: draft.date,
            period: draft.period,
            status: "pending",
            appointmentStatus: nil,
            decisionReason: nil,
            createdAt: Date())
        requests.insert(record, at: 0)
        notice = "Solicitud registrada como Pendiente. No es una cita."
        return nil
    }

    /// Ejemplos de diseño para comprobar los estados Rechazada y Cancelada. No son solicitudes reales.
    func addStateExamples() {
        guard !requests.contains(where: { $0.id == "ejemplo-rechazada" }) else { return }
        let rejected = ApplicantRequestRecord(
            id: "ejemplo-rechazada", specialty: "Pediatría", reason: "Consulta de control (ejemplo de diseño)",
            date: Date().addingTimeInterval(12 * 86400), period: "morning", status: "rejected", appointmentStatus: nil,
            decisionReason: "Ejemplo: la especialidad no tiene agenda en esa fecha.", createdAt: Date().addingTimeInterval(-86400))
        let cancelled = ApplicantRequestRecord(
            id: "ejemplo-cancelada", specialty: "Ginecología", reason: "Valoración general (ejemplo de diseño)",
            date: Date().addingTimeInterval(14 * 86400), period: "afternoon", status: "cancelled", appointmentStatus: nil,
            decisionReason: "Ejemplo: el solicitante canceló la solicitud.", createdAt: Date().addingTimeInterval(-2 * 86400))
        requests.append(contentsOf: [rejected, cancelled])
        notice = "Ejemplos de diseño añadidos: rechazada y cancelada. No son citas ni solicitudes reales."
    }

    /// Avance de ejemplo que simula a recepción. No modifica datos del hospital.
    func advance(_ id: String) {
        guard let index = requests.firstIndex(where: { $0.id == id }) else { return }
        switch requests[index].status {
        case "pending": requests[index].status = "identity_verified"
        case "identity_verified": requests[index].status = "converted"
        default:
            if requests[index].status == "converted", requests[index].appointmentStatus == nil {
                requests[index].appointmentStatus = "scheduled"
            }
        }
        notice = "Avance de ejemplo local. No se modificó ningún dato del hospital."
    }

    static func canAdvance(_ request: ApplicantRequestRecord) -> Bool {
        request.status == "pending" || request.status == "identity_verified"
            || (request.status == "converted" && request.appointmentStatus == nil)
    }
}
