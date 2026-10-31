import SwiftUI
import Combine

enum PatientAttentionState: String, Codable { case pending, scheduled, rejected, cancelled
    var label: String { ["pending":"Pendiente", "scheduled":"Cita asignada", "rejected":"Rechazada", "cancelled":"Cancelada"][rawValue] ?? rawValue }
}
struct PatientAttentionRequest: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    let givenName: String
    let familyName: String
    let dui: String
    let phone: String
    let email: String
    let specialty: String
    let reason: String
    let symptoms: [String]
    let preference: String
    let preferredSlot: String
    var state: PatientAttentionState = .pending
    var appointmentID: UUID? = nil
    var resolvedAt: Date? = nil
}
struct PatientAssignedAppointment: Identifiable {
    var id: UUID { appointment.id }
    let appointment: DoctorAppointment
    let date: Date
    let specialty: String
    let doctor: String
    let room: String
    let dui: String
    let email: String
}
@MainActor final class PatientAppointmentFlowStore: ObservableObject {
    @Published private(set) var requests: [PatientAttentionRequest] = []
    @Published private(set) var appointments: [PatientAssignedAppointment] = []
    init() { reset() }
    func reset() {
        let request = PatientAttentionRequest(id: UUID(), createdAt: Date(), givenName: PatientTestRecord.nombres, familyName: PatientTestRecord.apellidos, dui: PatientTestRecord.dui, phone: PatientTestRecord.telefono, email: PatientTestRecord.correo, specialty: "Médico general", reason: "Valoración de ejemplo", symptoms: ["Tos"], preference: "Mañana", preferredSlot: "Por confirmar")
        requests = [request]
        appointments = [makeAppointment(request: request, date: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)!)]
    }
    func submit(_ request: PatientAttentionRequest) -> Bool {
        guard !requests.contains(where: { $0.id == request.id }), request.state == .pending, request.appointmentID == nil,
            ["Mañana", "Tarde"].contains(request.preference), !request.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        requests.insert(request, at: 0); return true
    }
    @discardableResult func assignExample(id: UUID, date: Date, actor: String) -> Bool {
        guard actor == "reception-demo", date > Date(), let index = requests.firstIndex(where: { $0.id == id }), requests[index].state == .pending, requests[index].appointmentID == nil else { return false }
        let value = makeAppointment(request: requests[index], date: date)
        appointments.append(value); requests[index].appointmentID = value.id; requests[index].state = .scheduled; requests[index].resolvedAt = Date(); return true
    }
    private func makeAppointment(request: PatientAttentionRequest, date: Date) -> PatientAssignedAppointment {
        let end = date.addingTimeInterval(1800)
        return .init(appointment: .init(id: UUID(), patient_id: UUID(), patient_name: request.givenName + " " + request.familyName, record_number: "DEMO-EXP-001", phone: request.phone, ticket_number: nil,
            period: "[\"\(DoctorDate.timestamp(date))\",\"\(DoctorDate.timestamp(end))\")", status: "confirmed", encounter_id: nil, age: 29, reason: request.reason, symptoms: request.symptoms),
            date: date, specialty: request.specialty, doctor: "Dra. Ana Morales", room: "Consultorio 3", dui: request.dui, email: request.email)
    }
}
struct PatientAppointmentsView: View {
    @ObservedObject var flow: PatientAppointmentFlowStore
    @ObservedObject var modules: MobileModuleViewModel
    let profile: UserProfile?
    let patientID: UUID?
    let search: String
    let period: (String) -> String
    let navigate: (String) -> Void
    @State private var showDetail = false
    private var useExamples: Bool { modules.page != nil && modules.items.isEmpty && !modules.loading && modules.error == nil }
    private var next: PatientAssignedAppointment? {
        if useExamples { return flow.appointments.filter { $0.date >= Date() }.sorted { $0.date < $1.date }.first }
        guard let item = modules.items.filter({ ["scheduled", "confirmed"].contains($0.status) && (DoctorDate.parse($0.event_at) ?? .distantPast) >= Date() }).sorted(by: { (DoctorDate.parse($0.event_at) ?? .distantPast) < (DoctorDate.parse($1.event_at) ?? .distantPast) }).first, let date = DoctorDate.parse(item.event_at) else { return nil }
        func field(_ label: String) -> String? { item.details.first { $0.label.localizedCaseInsensitiveCompare(label) == .orderedSame }?.value }
        let value = DoctorAppointment(id: item.id, patient_id: patientID ?? item.id, patient_name: profile?.fullName ?? "No hay datos reales", record_number: "No hay datos reales", phone: field("Teléfono") ?? profile?.contacts.first { $0.kind == "phone" }?.value, ticket_number: nil,
            period: field("Horario") ?? "", status: item.status, encounter_id: nil, age: Int(field("Edad")?.components(separatedBy: " ").first ?? ""), reason: field("Motivo de la consulta") ?? item.subtitle, symptoms: field("Síntomas").map { $0.components(separatedBy: ",") })
        return .init(appointment: value, date: date, specialty: item.title, doctor: field("Medico") ?? "No hay datos reales", room: field("Consultorio") ?? "No hay datos reales", dui: field("DUI") ?? "No hay datos reales", email: field("Correo") ?? profile?.auth_email ?? "No hay datos reales")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let next, showDetail {
                DoctorConsultationTicketView(appointment: next.appointment, day: next.date, time: period(next.appointment.period), demonstration: useExamples, close: { showDetail = false }, embedded: true,
                    closeLabel: "Volver a Mis citas", context: [.init(label: "Especialidad", value: next.specialty), .init(label: "Médico", value: next.doctor), .init(label: "Consultorio", value: next.room), .init(label: "DUI", value: next.dui), .init(label: "Correo", value: next.email)])
            } else {
                PatientFormCard(titulo: "Próxima cita", icono: "calendar") {
                    if let next {
                        Text(next.date.formatted(date: .abbreviated, time: .shortened)).font(.title3.weight(.bold)).foregroundStyle(HospitalTheme.wine)
                        Text(next.appointment.patient_name).font(.headline)
                        HStack { DoctorConsultationField(label: "Edad", value: DoctorConsultationFields.age(next.appointment.age)); DoctorConsultationField(label: "Teléfono", value: DoctorConsultationFields.value(next.appointment.phone)) }
                        DoctorConsultationField(label: "Motivo de la consulta", value: DoctorConsultationFields.value(next.appointment.reason))
                        DoctorConsultationField(label: "Síntomas", value: DoctorConsultationFields.symptoms(next.appointment.symptoms))
                        Text(next.specialty).font(.subheadline.weight(.semibold)); Text(next.doctor).font(.footnote)
                        Text(next.room).font(.footnote); HospitalBadge(text: "Cita asignada")
                        if useExamples { Text("Cita de ejemplo · Sin reserva real").font(.caption) }
                        Button("Ver detalle de la cita") { showDetail = true }.buttonStyle(.bordered)
                    } else { Text("Todavía no tienes una próxima cita asignada.").font(.footnote) }
                }
                Button("Solicitar atención") { navigate("request") }.buttonStyle(HospitalPrimaryButtonStyle())
                PatientFormCard(titulo: "Mis solicitudes de ejemplo", icono: "clock") {
                    Text("Recepción debe asignar la cita. La preferencia no confirma disponibilidad.").font(.caption).foregroundStyle(HospitalTheme.secondary)
                    ForEach(flow.requests) { request in
                        HospitalCard {
                            Text(request.specialty).font(.subheadline.weight(.semibold)); HospitalBadge(text: request.state.label, warning: request.state == .pending)
                            Text(request.reason).font(.footnote)
                            Text("Solicitada: " + request.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                            Text("Preferencia: \(request.preference) · \(request.preferredSlot)").font(.caption)
                        }
                    }
                }
                if !modules.items.isEmpty || modules.error != nil || modules.loading {
                    MobileModuleView(model: modules, module: "appointments", role: "patient", search: search, period: period, navigate: navigate)
                }
            }
        }
    }
}
struct ReceptionAppointmentExampleView: View {
    @ObservedObject var flow: PatientAppointmentFlowStore
    @State private var date = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Recepción · Demostración local").font(.title2.bold())
            Text("No otorga permisos de recepcionista ni modifica Supabase.").font(.caption)
            DatePicker("Fecha y hora a asignar", selection: $date, in: Date()...)
            ForEach(flow.requests) { request in
                PatientFormCard(titulo: request.givenName + " " + request.familyName, icono: "person") {
                    Text("DUI: \(request.dui) · \(request.phone)").font(.footnote)
                    Text("Solicitada: " + request.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                    Text(request.email).font(.footnote); Text(request.specialty).font(.subheadline)
                    Text(request.reason).font(.footnote); Text("Síntomas: " + request.symptoms.joined(separator: ", ")).font(.footnote)
                    Text("Preferencia: \(request.preference) · \(request.preferredSlot)").font(.footnote)
                    HospitalBadge(text: request.state.label, warning: request.state == .pending)
                    Button("Asignar cita de ejemplo") { flow.assignExample(id: request.id, date: date, actor: "reception-demo") }.disabled(request.state != .pending)
                }
            }
        }.padding(17)
    }
}
private struct ReceptionAppointmentPreview: View {
    @StateObject private var flow = PatientAppointmentFlowStore()
    var body: some View { ScrollView { ReceptionAppointmentExampleView(flow: flow) } }
}
#Preview("Recepción · solicitudes locales") { ReceptionAppointmentPreview() }
