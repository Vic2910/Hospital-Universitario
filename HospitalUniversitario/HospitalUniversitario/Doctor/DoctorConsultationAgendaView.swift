import SwiftUI

/// Agenda visual: los ejemplos son locales y nunca entran al repositorio clínico.
struct DoctorConsultationAgendaView: View {
    @Binding var day: Date
    let appointments: [DoctorAppointment]
    let search: String
    let period: (String) -> String
    var demonstration = false
    let select: (UUID) -> Void
    @State private var ticket: DoctorAppointment?

    private var rows: [DoctorAppointment] {
        appointments.filter { search.isEmpty || ($0.patient_name + " " + $0.record_number).localizedCaseInsensitiveContains(search) }
            .sorted { $0.period < $1.period }
    }
    private var dateTitle: String {
        day.formatted(.dateTime.locale(Locale(identifier: "es_GT")).weekday(.wide).day().month(.wide))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Label("TU AGENDA", systemImage: "calendar").font(.system(size: 10, weight: .bold)).tracking(1.2)
                Text("Tus consultas, a tiempo").font(.system(size: 24, weight: .bold))
                Text(dateTitle).font(.subheadline)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(appointments.count)").font(.system(size: 36, weight: .bold))
                    Text((appointments.count == 1 ? "consulta" : "consultas") + (Calendar.current.isDateInToday(day) ? " para hoy" : " para esta fecha")).font(.footnote)
                }
            }.foregroundStyle(.white).padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient.vinoDestacado, in: RoundedRectangle(cornerRadius: 22))
            PatientFormCard(titulo: "Buscar por fecha", icono: "calendar.badge.clock") {
                DatePicker("Fecha de consultas", selection: $day, displayedComponents: .date).tint(HospitalTheme.wine)
                HStack(spacing: 8) {
                    dateButton("Hoy", offset: 0)
                    dateButton("Mañana", offset: 1)
                    dateButton("En 7 días", offset: 7)
                }
                Text("Elige una fecha para ver tu agenda y próximas consultas.").font(.footnote).foregroundStyle(HospitalTheme.secondary)
            }
            if demonstration {
                Text("Agenda de ejemplo · Datos precargados, sin reservas reales. No permiten iniciar ni guardar consultas.")
                    .font(.footnote).foregroundStyle(HospitalTheme.wine).padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 14))
            }
            Text(Calendar.current.isDateInToday(day) ? "Consultas de hoy" : "Consultas del día seleccionado").font(.system(size: 16, weight: .semibold))
            if rows.isEmpty {
                HospitalCard {
                    Label("No hay consultas para mostrar", systemImage: "calendar.badge.exclamationmark").font(.subheadline.weight(.semibold))
                    Text(search.isEmpty ? "Prueba otra fecha para revisar tu agenda." : "Ningún paciente coincide con tu búsqueda.").font(.footnote).foregroundStyle(HospitalTheme.secondary)
                }
            }
            ForEach(rows) { appointment in
                PatientFormCard(titulo: DoctorConsultationFields.value(appointment.patient_name), icono: "person") {
                    HStack {
                        Label(DoctorConsultationFields.time(period(appointment.period)), systemImage: "clock")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
                        Spacer()
                        Text(DoctorConsultationFields.status(appointment.status)).font(.caption.weight(.semibold))
                            .foregroundStyle(HospitalTheme.wine).padding(6).background(HospitalTheme.rose, in: Capsule())
                    }
                    HStack(alignment: .top, spacing: 16) {
                        DoctorConsultationField(label: "Edad", value: DoctorConsultationFields.age(appointment.age))
                        DoctorConsultationField(label: "Teléfono", value: DoctorConsultationFields.value(appointment.phone))
                    }
                    DoctorConsultationField(label: "Motivo de la consulta", value: DoctorConsultationFields.value(appointment.reason))
                    DoctorConsultationField(label: "Síntomas", value: DoctorConsultationFields.symptoms(appointment.symptoms))
                    Button("Ver detalle") { ticket = appointment }
                        .buttonStyle(.bordered).tint(HospitalTheme.wine)
                        .accessibilityLabel("Ver detalle de \(DoctorConsultationFields.value(appointment.patient_name))")
                }
            }
        }.foregroundStyle(HospitalTheme.ink)
        .onChange(of: day) { _, _ in ticket = nil }
        .sheet(item: $ticket) { appointment in
            DoctorConsultationTicketView(appointment: appointment, day: day, time: period(appointment.period), demonstration: demonstration,
                close: { ticket = nil }, openCare: demonstration ? nil : { ticket = nil; select(appointment.id) })
                .presentationDragIndicator(.visible)
        }
    }
    private func dateButton(_ label: String, offset: Int) -> some View {
        let target = Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date()))!
        return Button(label) { day = target }
            .font(.caption.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
            .background(Calendar.current.isDate(day, inSameDayAs: target) ? HospitalTheme.rose : HospitalTheme.background, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(HospitalTheme.wine).buttonStyle(.plain)
            .accessibilityAddTraits(Calendar.current.isDate(day, inSameDayAs: target) ? .isSelected : [])
    }
}

enum DoctorConsultationDemo {
    static func appointments(day: Date) -> [DoctorAppointment] {
        let calendar = Calendar.current
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: day)).day ?? -1
        let samples: [(Int, Int, Int, String, String)] = [
            (0, 8, 30, "Carlos Mendoza", "checked_in"), (0, 10, 0, "María López", "confirmed"),
            (0, 11, 30, "Juan Pérez", "scheduled"), (0, 14, 0, "Lucía García", "confirmed"),
            (1, 9, 0, "María López", "confirmed"), (1, 11, 0, "Carlos Mendoza", "scheduled"),
            (3, 10, 30, "Lucía García", "confirmed"), (7, 8, 30, "Juan Pérez", "scheduled")]
        return samples.enumerated().compactMap { index, sample in
            guard sample.0 == offset else { return nil }
            let from = calendar.date(bySettingHour: sample.1, minute: sample.2, second: 0, of: day)!
            let to = calendar.date(byAdding: .minute, value: 30, to: from)!
            let id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 301))!
            return DoctorAppointment(id: id, patient_id: id, patient_name: sample.3, record_number: "DEMO-\(index + 301)", phone: ["7123-4567", "7234-5678", "7356-7890", nil, "7234-5678", "7123-4567", nil, "7356-7890"][index], ticket_number: nil,
                period: "[\"\(DoctorDate.timestamp(from))\",\"\(DoctorDate.timestamp(to))\")", status: sample.4, encounter_id: nil,
                age: [42, 67, 35, 29, 67, 42, 29, 35][index],
                reason: ["Consulta de seguimiento", "Revisión de resultados", "Evaluación general", nil, "Revisión de resultados", "Consulta de seguimiento", nil, "Evaluación general"][index],
                symptoms: [["Tos", "Fiebre"], nil, ["Dolor de cabeza"], [], nil, ["Tos", "Fiebre"], [], ["Dolor de cabeza"]][index])
        }
    }
    static func period(_ value: String) -> String {
        let dates = value.split(separator: "\"").compactMap { DoctorDate.parse(String($0)) }
        guard dates.count == 2 else { return "Horario de ejemplo" }
        let format = DateFormatter(); format.locale = Locale(identifier: "es_GT"); format.dateFormat = "HH:mm"
        return format.string(from: dates[0]) + "–" + format.string(from: dates[1])
    }
}

private struct DoctorConsultationAgendaPreview: View {
    @State private var day = Date()
    var body: some View {
        ScrollView {
            DoctorConsultationAgendaView(day: $day, appointments: DoctorConsultationDemo.appointments(day: day), search: "",
                period: DoctorConsultationDemo.period, demonstration: true, select: { _ in }).padding(17)
        }.background(HospitalTheme.background)
    }
}
#Preview("Consultas · agenda local") { DoctorConsultationAgendaPreview() }
