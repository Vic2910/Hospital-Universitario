import SwiftUI

/// Componentes visuales del formulario de consulta: datos automáticos del paciente y de la cita,
/// bloques A (datos físicos), B (evaluación médica) y C (servicios adicionales).
/// Solo presentan datos reales recibidos de doctor_native_workspace / doctor_native_chart.
enum ConsultationFormat {
    private static let locale = Locale(identifier: "es_SV")
    static func date(_ date: Date?) -> String {
        guard let date else { return "No disponible" }
        let style = Date.FormatStyle(date: .complete, time: .omitted, locale: locale, calendar: DoctorClinicalRules.calendar, timeZone: DoctorClinicalRules.timeZone)
        let text = date.formatted(style)
        return text.prefix(1).uppercased() + text.dropFirst()
    }
    static func time(_ date: Date?) -> String {
        guard let date else { return "No disponible" }
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: DoctorClinicalRules.calendar, timeZone: DoctorClinicalRules.timeZone))
    }
    static func timeRange(_ appointment: DoctorAppointment) -> String {
        guard let start = appointment.startDate else { return "No disponible" }
        guard let minutes = appointment.duration_minutes, minutes > 0 else { return time(start) }
        return "\(time(start)) – \(time(start.addingTimeInterval(Double(minutes) * 60)))"
    }
    static func symptoms(_ appointment: DoctorAppointment) -> [String] {
        (appointment.symptoms ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

/// Distribuye etiquetas en varias líneas según el ancho disponible (síntomas, identificadores).
struct ConsultationFlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
                x += min(size.width, bounds.width) + spacing
            }
            y += row.height + spacing
        }
    }
    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }
    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [], current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let itemWidth = min(size.width, width)
            if !current.indices.isEmpty && current.width + spacing + itemWidth > width { rows.append(current); current = Row() }
            current.width += (current.indices.isEmpty ? 0 : spacing) + itemWidth
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// Tarjeta principal del paciente: nombre, estado, código/expediente y edad.
struct ConsultationPatientCard: View {
    let appointment: DoctorAppointment
    let patientCode: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                Text(DoctorAssignedPatient.initials(appointment.patient_name)).font(.title2.bold()).foregroundStyle(HospitalTheme.wine)
                    .frame(width: 64, height: 64).background(.white, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 4).padding(-4))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("PACIENTE").font(.caption2.weight(.heavy)).tracking(1.2).opacity(0.75)
                    Text(appointment.patient_name).font(.title2.bold()).lineLimit(3).minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            ConsultationFlowLayout(spacing: 8) {
                if let code = patientCode?.trimmingCharacters(in: .whitespaces), !code.isEmpty {
                    pill("number", "Código \(code)")
                }
                pill("folder", "Expediente \(appointment.record_number)")
                pill("person", DoctorConsultationFields.age(appointment.age))
                Label(DoctorClinicalRules.statusLabel(appointment.status), systemImage: statusIcon)
                    .font(.caption.bold()).foregroundStyle(HospitalTheme.wine)
                    .padding(.horizontal, 12).padding(.vertical, 7).background(.white, in: Capsule())
                    .accessibilityLabel("Estado: \(DoctorClinicalRules.statusLabel(appointment.status))")
            }
        }
        .foregroundStyle(.white).padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.vinoDestacado, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: HospitalTheme.wine.opacity(0.18), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
    }

    private var statusIcon: String {
        switch appointment.status {
        case "in_progress": return "stethoscope"
        case "completed": return "checkmark.seal.fill"
        case "cancelled", "no_show", "rejected": return "xmark.circle"
        default: return "calendar.badge.clock"
        }
    }
    private func pill(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon).font(.caption.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 7).background(Color.white.opacity(0.16), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
    }
}

/// Datos de la cita y de la solicitud del paciente, cargados automáticamente.
struct ConsultationAppointmentCard: View {
    let appointment: DoctorAppointment
    let doctorName: String
    let openedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ConsultationBlockHeader(icon: "calendar", title: "Datos de la cita", subtitle: "Información registrada por recepción y por el paciente")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12, alignment: .topLeading)], alignment: .leading, spacing: 12) {
                tile("calendar", "Fecha de la consulta", ConsultationFormat.date(appointment.startDate))
                tile("clock", "Hora de la consulta", ConsultationFormat.timeRange(appointment))
                tile("stethoscope", "Médico responsable", doctorName.isEmpty ? "No disponible" : doctorName)
                tile("cross.case", "Especialidad", appointment.specialty ?? "Cita directa de recepción")
                tile("door.left.hand.open", "Consultorio", appointment.room_code ?? "No asignado")
                if let openedAt { tile("play.circle", "Consulta abierta a las", ConsultationFormat.time(openedAt)) }
                else if let ticket = appointment.ticket_number, !ticket.isEmpty { tile("ticket", "Turno", ticket) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Label("Motivo de consulta enviado por el paciente", systemImage: "text.bubble").font(.subheadline.weight(.semibold))
                    .foregroundStyle(HospitalTheme.ink)
                Text(appointment.reason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "La cita no tiene una solicitud de atención vinculada.")
                    .font(.body).foregroundStyle(appointment.reason == nil ? HospitalTheme.secondary : HospitalTheme.ink)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(HospitalTheme.rose.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .leading) { Rectangle().fill(HospitalTheme.wine).frame(width: 4).clipShape(Capsule()).padding(.vertical, 10) }
            }
        }
        .modifier(ConsultationCardStyle())
    }

    private func tile(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
                .frame(width: 32, height: 32).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(HospitalTheme.secondary)
                Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(HospitalTheme.ink).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Síntomas que el paciente marcó en su solicitud, para revisarlos antes de escribir.
struct ConsultationReportedSymptoms: View {
    let symptoms: [String]
    let other: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Referidos por el paciente en su solicitud", systemImage: "person.wave.2").font(.caption.weight(.semibold))
                .foregroundStyle(HospitalTheme.secondary)
            if symptoms.isEmpty && (other?.isEmpty ?? true) {
                Text("El paciente no indicó síntomas en la solicitud.").font(.footnote).foregroundStyle(HospitalTheme.secondary)
            } else {
                ConsultationFlowLayout(spacing: 6) {
                    ForEach(symptoms, id: \.self) { symptom in
                        Text(symptom).font(.footnote.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
                            .padding(.horizontal, 11).padding(.vertical, 6).background(HospitalTheme.rose, in: Capsule())
                    }
                }
                if let other, !other.isEmpty { Text("Otros: \(other)").font(.footnote).foregroundStyle(HospitalTheme.ink) }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Encabezado de cada bloque del formulario.
struct ConsultationBlockHeader: View {
    var letter: String? = nil
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: icon).font(.title3.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(LinearGradient.vinoDestacado, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                if let letter {
                    Text(letter).font(.caption2.weight(.heavy)).foregroundStyle(HospitalTheme.wine)
                        .frame(width: 20, height: 20).background(.white, in: Circle()).overlay(Circle().stroke(HospitalTheme.rose, lineWidth: 2))
                        .offset(x: 6, y: 6)
                }
            }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(letter.map { "\($0). \(title)" } ?? title).font(.headline).foregroundStyle(HospitalTheme.ink)
                Text(subtitle).font(.caption).foregroundStyle(HospitalTheme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
    }
}

/// Campo numérico grande con unidad visible; no admite letras (DoctorClinicalRules.sanitize).
struct ConsultationMeasureField: View {
    let vital: DoctorClinicalRules.Vital
    let icon: String
    @Binding var value: String
    let issue: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
                    .frame(width: 30, height: 30).background(HospitalTheme.rose, in: Circle())
                Text(vital.label).font(.subheadline.weight(.semibold)).foregroundStyle(HospitalTheme.ink)
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("—", text: Binding(get: { value }, set: { value = DoctorClinicalRules.sanitize($0, integer: vital.integer) }))
                    .keyboardType(.decimalPad).font(.system(.title, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(HospitalTheme.ink).minimumScaleFactor(0.7)
                    .accessibilityLabel("\(vital.label) en \(vital.unit)")
                Text(vital.unit).font(.headline).foregroundStyle(HospitalTheme.wine)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(issue == nil ? HospitalTheme.secondary.opacity(0.15) : HospitalTheme.wine, lineWidth: issue == nil ? 1 : 1.5))
            Text(issue ?? hint).font(.caption2.weight(issue == nil ? .regular : .semibold))
                .foregroundStyle(issue == nil ? HospitalTheme.secondary : HospitalTheme.wine).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(HospitalTheme.rose, lineWidth: 1))
    }

    private var hint: String {
        let lower = vital.lowerExclusive ? "Mayor que \(Int(vital.range.lowerBound))" : "Desde \(Int(vital.range.lowerBound))"
        return "\(lower) hasta \(Int(vital.range.upperBound)) \(vital.unit) · opcional"
    }
}

/// Campo de texto amplio para síntomas, diagnóstico y observaciones.
struct ConsultationNoteField<Accessory: View>: View {
    let icon: String
    let title: String
    let placeholder: String
    @Binding var text: String
    var hint: String? = nil
    @ViewBuilder var accessory: Accessory

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
                    .frame(width: 30, height: 30).background(HospitalTheme.rose, in: Circle())
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(HospitalTheme.ink)
                Spacer(minLength: 0)
                Label(isEmpty ? "Obligatorio" : "Completo", systemImage: isEmpty ? "asterisk" : "checkmark.circle.fill")
                    .font(.caption2.bold()).foregroundStyle(isEmpty ? HospitalTheme.wine : Color(red: 0.13, green: 0.5, blue: 0.3))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(isEmpty ? HospitalTheme.rose : HospitalTheme.green, in: Capsule())
            }
            accessory
            TextField(placeholder, text: $text, axis: .vertical).lineLimit(4...14).font(.body)
                .padding(14).frame(minHeight: 110, alignment: .topLeading)
                .background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(isEmpty ? HospitalTheme.rose : HospitalTheme.secondary.opacity(0.15), lineWidth: isEmpty ? 1.5 : 1))
                .accessibilityLabel(title + ", obligatorio para finalizar")
            if let hint { Text(hint).font(.caption).foregroundStyle(HospitalTheme.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

extension ConsultationNoteField where Accessory == EmptyView {
    init(icon: String, title: String, placeholder: String, text: Binding<String>, hint: String? = nil) {
        self.init(icon: icon, title: title, placeholder: placeholder, text: text, hint: hint) { EmptyView() }
    }
}

/// Acceso a un servicio adicional (exámenes o receta) que abre el formulario existente.
struct ConsultationServiceButton: View {
    let icon: String
    let title: String
    let subtitle: String
    var badge: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title2.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
                    .frame(width: 52, height: 52).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(HospitalTheme.ink)
                    Text(subtitle).font(.caption).foregroundStyle(HospitalTheme.secondary).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let badge {
                        Text(badge).font(.caption2.bold()).foregroundStyle(HospitalTheme.wine)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(HospitalTheme.rose, in: Capsule())
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.subheadline.weight(.bold)).foregroundStyle(HospitalTheme.wine.opacity(0.7))
            }
            .padding(14).frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(HospitalTheme.rose, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Abre el formulario sin salir de la consulta")
    }
}

/// Tarjeta blanca de bloque con sombra suave.
struct ConsultationCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: HospitalTheme.ink.opacity(0.06), radius: 12, y: 4)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
