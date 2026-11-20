import SwiftUI

/// Agenda médica: dos filtros (PENDIENTES y FINALIZADAS), fecha compacta y búsqueda.
/// Reglas en DoctorClinicalRules.pending/finished (espejo de HospitalCore.doctorClinical). Los estados no se modifican:
/// canceladas y no asistidas no aparecen en ninguno de los dos filtros. Los ejemplos son locales y nunca entran al repositorio clínico.
struct DoctorConsultationAgendaView: View {
    @Binding var day: Date
    let appointments: [DoctorAppointment]
    let search: String
    let period: (String) -> String
    var demonstration = false
    var statusFilter: Binding<String>? = nil
    let select: (UUID) -> Void
    @State private var ticket: DoctorAppointment?
    @State private var localFilter = "pending"
    @State private var query = ""
    @State private var showCalendar = false

    private var filter: Binding<String> { statusFilter ?? $localFilter }
    private var calendar: Calendar { DoctorClinicalRules.calendar }
    private var isToday: Bool { calendar.isDate(day, inSameDayAs: Date()) }
    private func visible(_ list: [DoctorAppointment]) -> [DoctorAppointment] {
        list.filter { DoctorClinicalRules.matches($0, query: query) && DoctorClinicalRules.matches($0, query: search) }
    }

    var body: some View {
        let pending = visible(DoctorClinicalRules.pending(appointments, day: day))
        let finished = visible(DoctorClinicalRules.finished(appointments, day: day))
        let showFinished = filter.wrappedValue == "finished"
        let rows = showFinished ? finished : pending
        VStack(alignment: .leading, spacing: 14) {
            header(pending: pending.count, finished: finished.count)
            dateBar
            searchField
            if demonstration {
                Text("Agenda de ejemplo · Datos precargados, sin reservas reales. No permiten iniciar ni guardar consultas.")
                    .font(.footnote).foregroundStyle(HospitalTheme.wine).padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                Text(showFinished ? "Consultas finalizadas" : "Consultas pendientes").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(showFinished ? "Última finalizada primero" : "Por hora").font(.caption).foregroundStyle(HospitalTheme.secondary)
            }
            if rows.isEmpty { emptyState(finished: showFinished) }
            LazyVStack(spacing: 10) {
                ForEach(rows) { appointment in card(appointment, finished: showFinished) }
            }
            // Canceladas y no atendidas: conservan su estado y su turno; nunca se cuentan como consultas atendidas.
            let closed = showFinished ? visible(DoctorClinicalRules.closedWithoutCare(appointments, day: day)) : []
            if !closed.isEmpty {
                Text("Canceladas y no atendidas").font(.headline).padding(.top, 6).accessibilityAddTraits(.isHeader)
                LazyVStack(spacing: 10) { ForEach(closed) { appointment in card(appointment, finished: false) } }
            }
        }
        .foregroundStyle(HospitalTheme.ink)
        .onChange(of: day) { _, _ in ticket = nil }
        .sheet(item: $ticket) { appointment in
            DoctorConsultationTicketView(appointment: appointment, day: day, time: period(appointment.period), demonstration: demonstration,
                close: { ticket = nil }, openCare: demonstration ? nil : { ticket = nil; select(appointment.id) })
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCalendar) { calendarSheet.presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
    }

    // MARK: Cabecera con indicadores-filtro

    private func header(pending: Int, finished: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("AGENDA MÉDICA", systemImage: "calendar").font(.caption2.weight(.heavy)).tracking(1.2).opacity(0.85)
                    Text("Consultas").font(.system(size: 28, weight: .bold))
                }
                Spacer()
                Text(longDate).font(.caption.weight(.semibold)).multilineTextAlignment(.trailing).opacity(0.9)
            }
            HStack(spacing: 10) {
                indicator("pending", "Pendientes", pending, icon: "clock.badge")
                indicator("finished", "Finalizadas", finished, icon: "checkmark.seal.fill")
            }
        }
        .foregroundStyle(.white).padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.vinoDestacado, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: HospitalTheme.wine.opacity(0.18), radius: 12, y: 5)
    }

    private func indicator(_ value: String, _ title: String, _ count: Int, icon: String) -> some View {
        let selected = filter.wrappedValue == value
        return Button { withAnimation(.easeInOut(duration: 0.15)) { filter.wrappedValue = value } } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.headline)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(count)").font(.system(size: 24, weight: .bold).monospacedDigit())
                    Text(title.uppercased()).font(.caption2.weight(.bold)).tracking(0.6)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? HospitalTheme.wine : .white)
            .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, minHeight: 60)
            .background(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.15)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(count)")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: Fecha y búsqueda

    private var dateBar: some View {
        HStack(spacing: 8) {
            stepButton("chevron.left", label: "Día anterior", offset: -1)
            Button { showCalendar = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "calendar").foregroundStyle(HospitalTheme.wine)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(relativeDay).font(.caption2.weight(.bold)).foregroundStyle(HospitalTheme.wine)
                        Text(shortDate).font(.subheadline.weight(.semibold)).foregroundStyle(HospitalTheme.ink)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.caption.bold()).foregroundStyle(HospitalTheme.secondary)
                }.padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.plain).accessibilityLabel("Fecha consultada: \(longDate). Cambiar fecha")
            stepButton("chevron.right", label: "Día siguiente", offset: 1)
            Button("Hoy") { day = calendar.startOfDay(for: Date()) }
                .font(.subheadline.bold()).padding(.horizontal, 12).frame(minHeight: 40)
                .foregroundStyle(isToday ? HospitalTheme.secondary : .white)
                .background(isToday ? AnyShapeStyle(HospitalTheme.background) : AnyShapeStyle(LinearGradient.vinoDestacado), in: Capsule())
                .buttonStyle(.plain).disabled(isToday)
        }
        .padding(6).background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(HospitalTheme.rose, lineWidth: 1))
    }

    private func stepButton(_ icon: String, label: String, offset: Int) -> some View {
        Button { if let next = calendar.date(byAdding: .day, value: offset, to: day) { day = next } } label: {
            Image(systemName: icon).font(.subheadline.bold()).foregroundStyle(HospitalTheme.wine)
                .frame(width: 40, height: 40).background(HospitalTheme.rose, in: Circle())
        }.buttonStyle(.plain).accessibilityLabel(label)
    }

    private var calendarSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                DatePicker("Fecha de consultas", selection: $day, displayedComponents: .date)
                    .datePickerStyle(.graphical).tint(HospitalTheme.wine).environment(\.timeZone, DoctorClinicalRules.timeZone)
                    .environment(\.locale, Locale(identifier: "es_SV"))
                Button("Ir a hoy") { day = calendar.startOfDay(for: Date()); showCalendar = false }
                    .buttonStyle(.bordered).tint(HospitalTheme.wine)
                Spacer(minLength: 0)
            }.padding()
            .navigationTitle("Elegir fecha").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { showCalendar = false } } }
        }
        .onChange(of: day) { _, _ in showCalendar = false }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(HospitalTheme.wine)
            TextField("Paciente, código o expediente", text: $query)
                .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                .accessibilityLabel("Buscar consultas")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(HospitalTheme.secondary) }
                    .accessibilityLabel("Borrar búsqueda")
            }
        }
        .padding(.horizontal, 14).frame(minHeight: 46)
        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(HospitalTheme.rose, lineWidth: 1))
    }

    // MARK: Tarjetas

    private func card(_ appointment: DoctorAppointment, finished: Bool) -> some View {
        let start = appointment.startDate
        let inProgress = appointment.status == "in_progress"
        let earlier = start.map { !calendar.isDate($0, inSameDayAs: day) } ?? false
        return Button { ticket = appointment } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 2) {
                    Text(hour(start)).font(.system(size: 20, weight: .bold).monospacedDigit())
                    Text(meridiem(start)).font(.caption2.weight(.bold))
                    if let minutes = appointment.duration_minutes, minutes > 0 { Text("\(minutes) min").font(.caption2).opacity(0.8) }
                }
                .foregroundStyle(inProgress ? .white : HospitalTheme.wine)
                .frame(width: 74).padding(.vertical, 12)
                .background(inProgress ? AnyShapeStyle(LinearGradient.vinoDestacado) : AnyShapeStyle(HospitalTheme.rose), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(DoctorConsultationFields.value(appointment.patient_name)).font(.headline).foregroundStyle(HospitalTheme.ink)
                            .multilineTextAlignment(.leading).lineLimit(2)
                        Spacer(minLength: 4)
                        statusBadge(appointment.status)
                    }
                    if let reason = DoctorRecordRules.text(appointment.reason) {
                        Text(reason).font(.subheadline).foregroundStyle(HospitalTheme.ink.opacity(0.85)).lineLimit(2).multilineTextAlignment(.leading)
                    }
                    HStack(spacing: 10) {
                        Label(appointment.room_code.map { "Consultorio \($0)" } ?? "Sin consultorio", systemImage: "door.left.hand.open")
                        Label(DoctorRecordRules.text(appointment.patient_code) ?? appointment.record_number, systemImage: "folder")
                    }.font(.caption).foregroundStyle(HospitalTheme.secondary).lineLimit(1)
                    if finished {
                        Label(appointment.finishedDate.map { "Finalizada a las \(ConsultationFormat.time($0))" } ?? "Finalizada · hora de la cita", systemImage: "checkmark.seal")
                            .font(.caption.weight(.semibold)).foregroundStyle(Color(red: 0.13, green: 0.5, blue: 0.3))
                    } else if earlier, let start {
                        Label("Abierta el \(start.formatted(.dateTime.locale(Locale(identifier: "es_SV")).weekday(.abbreviated).day().month(.abbreviated)))", systemImage: "exclamationmark.circle")
                            .font(.caption.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(HospitalTheme.wine.opacity(0.7)).padding(.top, 6)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(inProgress ? HospitalTheme.wine : HospitalTheme.rose, lineWidth: inProgress ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ver detalle de \(DoctorConsultationFields.value(appointment.patient_name)), \(DoctorConsultationFields.status(appointment.status))")
    }

    private func statusBadge(_ status: String) -> some View {
        let inProgress = status == "in_progress", done = status == "completed"
        return Text(DoctorClinicalRules.statusLabel(status)).font(.caption2.weight(.bold))
            .foregroundStyle(inProgress ? .white : done ? Color(red: 0.13, green: 0.5, blue: 0.3) : HospitalTheme.wine)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(inProgress ? AnyShapeStyle(HospitalTheme.wine) : AnyShapeStyle(done ? HospitalTheme.green : HospitalTheme.rose), in: Capsule())
    }

    private func emptyState(finished: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: finished ? "checkmark.seal" : "calendar.badge.checkmark").font(.system(size: 28, weight: .semibold))
                .foregroundStyle(HospitalTheme.wine).frame(width: 58, height: 58).background(HospitalTheme.rose, in: Circle())
            Text(!query.isEmpty || !search.isEmpty ? "Sin coincidencias" : finished ? "Aún no hay consultas finalizadas" : "No tienes consultas pendientes")
                .font(.subheadline.weight(.semibold))
            Text(!query.isEmpty || !search.isEmpty ? "Ningún paciente de esta fecha coincide con la búsqueda." :
                    finished ? "Las consultas que finalices en esta fecha aparecerán aquí." : "No hay citas por atender en esta fecha.")
                .font(.footnote).foregroundStyle(HospitalTheme.secondary).multilineTextAlignment(.center)
        }.padding(20).frame(maxWidth: .infinity).background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Formato (America/El_Salvador)

    private func style(_ format: Date.FormatStyle) -> Date.FormatStyle {
        var value = format; value.timeZone = DoctorClinicalRules.timeZone; value.calendar = calendar; value.locale = Locale(identifier: "es_SV"); return value
    }
    private func hour(_ date: Date?) -> String {
        guard let date else { return "--:--" }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let h = (parts.hour ?? 0) % 12 == 0 ? 12 : (parts.hour ?? 0) % 12
        return String(format: "%d:%02d", h, parts.minute ?? 0)
    }
    private func meridiem(_ date: Date?) -> String {
        guard let date else { return "" }
        return (calendar.component(.hour, from: date) < 12) ? "a. m." : "p. m."
    }
    private var shortDate: String { day.formatted(style(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())) }
    private var longDate: String { day.formatted(style(.dateTime.weekday(.wide).day().month(.wide))) }
    private var relativeDay: String {
        if isToday { return "HOY" }
        let today = calendar.startOfDay(for: Date()), target = calendar.startOfDay(for: day)
        let offset = calendar.dateComponents([.day], from: today, to: target).day ?? 0
        return offset == -1 ? "AYER" : offset == 1 ? "MAÑANA" : offset < 0 ? "HACE \(-offset) DÍAS" : "EN \(offset) DÍAS"
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
