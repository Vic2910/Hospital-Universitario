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
/// Mis citas: todos los detalles a la vista, sin pantallas intermedias. Paridad con web-preview/patient-appointments.js.
/// Datos reales del módulo "appointments" (RLS del paciente); la cancelación usa la acción existente cancel_appointment.
struct PatientAppointmentsView: View {
    @ObservedObject var flow: PatientAppointmentFlowStore
    @ObservedObject var modules: MobileModuleViewModel
    let profile: UserProfile?
    let patientID: UUID?
    let search: String
    let period: (String) -> String
    let navigate: (String) -> Void
    @State private var cancelling: MobileItem?
    @State private var cancellationReason = ""

    private func date(_ item: MobileItem) -> Date { DoctorDate.parse(item.event_at) ?? .distantPast }
    private var visible: [MobileItem] {
        modules.items.filter { search.isEmpty || ($0.title + " " + $0.details.map(\.value).joined(separator: " ")).localizedCaseInsensitiveContains(search) }
    }
    /// En atención o programadas a futuro, de la más próxima a la más lejana.
    private var upcoming: [MobileItem] {
        visible.filter { $0.status == "in_progress" || (["scheduled", "confirmed"].contains($0.status) && date($0) >= Date().addingTimeInterval(-1800)) }
            .sorted { date($0) < date($1) }
    }
    /// Finalizadas, canceladas o pasadas, de la más reciente a la más antigua.
    private var past: [MobileItem] {
        let ids = Set(upcoming.map(\.id))
        return visible.filter { !ids.contains($0.id) }.sorted { date($0) > date($1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label("MIS CITAS", systemImage: "calendar").font(.caption2.weight(.heavy)).tracking(1.2).opacity(0.85)
                Text(upcoming.isEmpty ? "No tienes citas próximas" : upcoming.count == 1 ? "Tienes 1 cita próxima" : "Tienes \(upcoming.count) citas próximas").font(.title2.bold())
                Text("Recepción programa tus citas. Aquí ves la fecha, el médico, el consultorio y el motivo.").font(.subheadline).opacity(0.9)
            }.foregroundStyle(.white).padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient.vinoDestacado, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            if modules.loading && modules.items.isEmpty { ProgressView("Cargando tus citas…").frame(maxWidth: .infinity) }
            if let error = modules.error {
                HospitalNotice(text: error)
                Button("Reintentar", systemImage: "arrow.clockwise") { Task { await modules.load("appointments") } }.tint(HospitalTheme.wine)
            }
            if let confirmation = modules.confirmation { Label(confirmation, systemImage: "checkmark.circle.fill").font(.footnote.weight(.semibold)).foregroundStyle(HospitalTheme.wine) }
            if let next = upcoming.first {
                appointmentCard(next, featured: true)
                if upcoming.count > 1 {
                    sectionTitle("Siguientes citas", count: upcoming.count - 1)
                    ForEach(upcoming.dropFirst()) { appointmentCard($0, featured: false) }
                }
            } else if !modules.loading && modules.error == nil {
                VStack(spacing: 10) {
                    Image(systemName: "calendar.badge.plus").font(.system(size: 30, weight: .semibold)).foregroundStyle(HospitalTheme.wine)
                        .frame(width: 64, height: 64).background(HospitalTheme.rose, in: Circle())
                    Text("Sin citas programadas").font(.headline)
                    Text("Cuando recepción programe tu atención, verás aquí la fecha, la hora y el consultorio.").font(.subheadline).foregroundStyle(HospitalTheme.secondary).multilineTextAlignment(.center)
                    Button { navigate("request") } label: { Label("Solicitar atención", systemImage: "stethoscope").font(.headline).frame(maxWidth: .infinity, minHeight: 46) }
                        .buttonStyle(.bordered).tint(HospitalTheme.wine)
                }.padding(22).frame(maxWidth: .infinity).background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            if !past.isEmpty {
                sectionTitle("Historial de citas", count: past.count)
                ForEach(past) { appointmentCard($0, featured: false) }
            }
            if modules.page?.has_more == true {
                Button("Cargar más citas") { Task { await modules.load("appointments", more: true) } }.frame(maxWidth: .infinity).disabled(modules.loading).tint(HospitalTheme.wine)
            }
        }
        .alert("Cancelar cita", isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } })) {
            TextField("Motivo de cancelación", text: $cancellationReason)
            Button("Cancelar cita", role: .destructive) {
                if let item = cancelling { let reason = cancellationReason; Task { await modules.cancel(item, reason: reason) } }
                cancelling = nil
            }.disabled(cancellationReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Volver", role: .cancel) { cancelling = nil }
        } message: { Text("Recepción verá el motivo. Esta acción no se puede deshacer.") }
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).font(.headline).foregroundStyle(HospitalTheme.ink)
            Spacer()
            Text("\(count)").font(.caption.bold()).foregroundStyle(HospitalTheme.wine).padding(.horizontal, 10).padding(.vertical, 4).background(HospitalTheme.rose, in: Capsule())
        }.padding(.top, 4)
    }

    private func value(_ item: MobileItem, _ label: String) -> String? {
        guard let text = item.details.first(where: { $0.label.localizedCaseInsensitiveCompare(label) == .orderedSame })?.value.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text != "Sin registrar" else { return nil }
        return text
    }

    private func appointmentCard(_ item: MobileItem, featured: Bool) -> some View {
        let start = DoctorDate.parse(item.event_at)
        let status = DoctorClinicalRules.statusLabel(item.status)
        let active = ["scheduled", "confirmed", "in_progress"].contains(item.status)
        let rows: [(String, String, String?)] = [("stethoscope", "Médico", value(item, "Médico")), ("cross.case", "Especialidad", value(item, "Especialidad")),
            ("door.left.hand.open", "Consultorio", value(item, "Consultorio")), ("text.bubble", "Motivo", value(item, "Motivo de la consulta")),
            ("xmark.circle", "Motivo de cancelación", value(item, "Motivo de cancelación"))]
        let present = rows.compactMap { row in row.2.map { (row.0, row.1, $0) } }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 2) {
                    Text(start.map { $0.formatted(Date.FormatStyle(locale: Locale(identifier: "es_SV"), calendar: DoctorClinicalRules.calendar, timeZone: DoctorClinicalRules.timeZone).day()) } ?? "--")
                        .font(.system(size: featured ? 28 : 22, weight: .bold))
                    Text(start.map { $0.formatted(Date.FormatStyle(locale: Locale(identifier: "es_SV"), calendar: DoctorClinicalRules.calendar, timeZone: DoctorClinicalRules.timeZone).month(.abbreviated)) }?.uppercased() ?? "")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(featured ? .white : HospitalTheme.wine)
                .frame(width: featured ? 66 : 56, height: featured ? 70 : 60)
                .background(featured ? AnyShapeStyle(LinearGradient.vinoDestacado) : AnyShapeStyle(HospitalTheme.rose), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    if featured { Text("PRÓXIMA CITA").font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(HospitalTheme.wine) }
                    Text(item.title).font(featured ? .title3.bold() : .headline).foregroundStyle(HospitalTheme.ink)
                    Text(start.map { $0.formatted(Date.FormatStyle(date: .complete, time: .omitted, locale: Locale(identifier: "es_SV"), calendar: DoctorClinicalRules.calendar, timeZone: DoctorClinicalRules.timeZone)) } ?? "Fecha no disponible")
                        .font(.caption).foregroundStyle(HospitalTheme.secondary)
                    Label(value(item, "Horario").map { period($0) } ?? "Horario no disponible", systemImage: "clock").font(.subheadline.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
                }
                Spacer(minLength: 0)
                Text(status).font(.caption2.bold()).padding(.horizontal, 8).padding(.vertical, 4)
                    .foregroundStyle(item.status == "in_progress" ? .white : item.status == "completed" ? Color(red: 0.13, green: 0.5, blue: 0.3) : active ? HospitalTheme.wine : HospitalTheme.secondary)
                    .background(item.status == "in_progress" ? AnyShapeStyle(HospitalTheme.wine) : AnyShapeStyle(item.status == "completed" ? HospitalTheme.green : active ? HospitalTheme.rose : HospitalTheme.background), in: Capsule())
            }
            if !present.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(present.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: row.0).font(.footnote.weight(.semibold)).foregroundStyle(HospitalTheme.wine).frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.1).font(.caption2).foregroundStyle(HospitalTheme.secondary)
                                Text(row.2).font(.subheadline).foregroundStyle(HospitalTheme.ink).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if featured && item.status == "in_progress" {
                Label("Tu médico ya inició la consulta.", systemImage: "stethoscope").font(.footnote.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
            } else if featured && active {
                Label("Llega 15 minutos antes y presenta tu DUI en recepción.", systemImage: "info.circle").font(.footnote).foregroundStyle(HospitalTheme.secondary)
            }
            if item.action == "cancel_appointment" {
                Button(role: .destructive) { cancellationReason = ""; cancelling = item } label: {
                    Label("Cancelar cita", systemImage: "calendar.badge.minus").font(.subheadline.weight(.semibold))
                }.disabled(modules.saving)
            }
        }
        .padding(featured ? 18 : 14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(featured ? HospitalTheme.wine.opacity(0.35) : HospitalTheme.rose, lineWidth: featured ? 1.5 : 1))
        .shadow(color: HospitalTheme.ink.opacity(featured ? 0.07 : 0.03), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
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
