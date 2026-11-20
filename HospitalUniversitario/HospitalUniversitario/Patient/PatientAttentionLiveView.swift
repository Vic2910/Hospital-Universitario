import SwiftUI

/// Cuenta → solicitud; recepción conserva el control del expediente y la cita.
@MainActor
struct PatientAttentionLiveView: View {
    @ObservedObject var model: PatientAttentionModel
    let navigate: (String) -> Void
    @State private var showPreviousRequests = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            hero
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark").font(.caption.weight(.heavy)).foregroundStyle(.white)
                    .frame(width: 22, height: 22).background(Color(red: 0.89, green: 0.64, blue: 0.23), in: Circle())
                Text("Este formulario no es para emergencias. Ante una emergencia, acude a urgencias. Los síntomas declarados no son diagnósticos.")
                    .font(.caption).foregroundStyle(Color(red: 0.44, green: 0.33, blue: 0.13)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 1, green: 0.97, blue: 0.91), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(red: 0.95, green: 0.87, blue: 0.71), lineWidth: 1))
            .accessibilityElement(children: .combine)
            if model.loading { ProgressView("Cargando tus datos y solicitudes…").frame(maxWidth: .infinity) }
            if let error = model.error { HospitalNotice(text: error) }
            if let confirmation = model.confirmation {
                Label(confirmation, systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Color(red: 0.12, green: 0.42, blue: 0.24))
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 0.91, green: 0.96, blue: 0.93), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            if let blocker = model.submissionBlocker, model.context != nil {
                // Una sola solicitud activa: recepción debe programarla o rechazarla antes de enviar otra.
                let reviewing = model.requests.contains { AttentionRules.openStates.contains($0.status) }
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: reviewing ? "hourglass" : "calendar.badge.checkmark")
                        .font(.title.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
                        .frame(width: 60, height: 60).background(HospitalTheme.rose, in: Circle())
                    Text(reviewing ? "Tu solicitud está en revisión" : "Ya tienes una cita programada")
                        .font(.title3.bold()).foregroundStyle(HospitalTheme.ink)
                    Text(blocker).font(.subheadline).foregroundStyle(HospitalTheme.secondary).fixedSize(horizontal: false, vertical: true)
                    Button { navigate("appointments") } label: {
                        Label("Ver mis citas", systemImage: "calendar").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.bordered).tint(HospitalTheme.wine)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(HospitalTheme.rose, lineWidth: 1.5))
                    .accessibilityElement(children: .combine)
            } else if let context = model.context {
                personalCard(context.person)
                symptomsCard(context)
                specialtyCard(context)
                detailsCard(context)
            } else if !model.loading && model.error == nil {
                Button("Cargar formulario") { Task { await model.load() } }
            }
            history
        }
        .disabled(model.saving)
        .accessibilityIdentifier("patient-attention-form")
    }

    /// Encabezado con los tres pasos (paridad con .req-hero de web-preview).
    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NUEVA SOLICITUD").font(.caption2.weight(.heavy)).tracking(1.4).opacity(0.85)
                Spacer()
                Button("Actualizar") { Task { await model.load() } }
                    .font(.caption.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.white.opacity(0.14), in: Capsule()).overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
                    .buttonStyle(.plain).disabled(model.loading || model.saving)
            }
            Text("¿Cómo podemos ayudarte?").font(.title2.bold())
            Text("Cuéntanos qué sientes. Recepción revisará tu solicitud y te asignará una cita.").font(.subheadline).opacity(0.9)
            HStack(spacing: 8) {
                ForEach(Array(["Síntomas", "Especialidad", "Detalles"].enumerated()), id: \.offset) { index, label in
                    HStack(spacing: 6) {
                        Text("\(index + 1)").font(.caption2.weight(.heavy)).foregroundStyle(HospitalTheme.wine)
                            .frame(width: 20, height: 20).background(Color.white, in: Circle())
                        Text(label).font(.caption2.weight(.bold)).lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }.padding(.top, 4)
        }
        .foregroundStyle(.white).padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.vinoDestacado, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func stepHeader(_ number: String, _ title: String, _ hint: String?, count: String? = nil, highlighted: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.subheadline.weight(.heavy)).foregroundStyle(HospitalTheme.wine)
                .frame(width: 30, height: 30).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(HospitalTheme.ink)
                if let hint { Text(hint).font(.caption).foregroundStyle(HospitalTheme.secondary) }
                if let count {
                    Text(count).font(.caption2.weight(.bold)).foregroundStyle(highlighted ? HospitalTheme.wine : HospitalTheme.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(highlighted ? HospitalTheme.rose : HospitalTheme.background, in: Capsule()).padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func cardStyle<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(HospitalTheme.rose, lineWidth: 1))
            .shadow(color: HospitalTheme.ink.opacity(0.05), radius: 9, y: 4)
    }

    /// Tus datos: resumen compacto de la cuenta; solo se piden los datos que faltan.
    private func personalCard(_ person: AttentionPerson) -> some View {
        let name = [person.first_name, person.last_name].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
        let initials = name.split(separator: " ").prefix(2).compactMap { $0.first.map { String($0).uppercased() } }.joined()
        let candidates: [(String, String?)] = [("DUI", person.dui), ("Nacimiento", displayDate(person.birth_date)), ("Teléfono", person.phone)]
        let facts: [(String, String)] = candidates.compactMap { item in model.isMissing(item.1) ? nil : (item.0, item.1 ?? "") }
        let missing: [(String, String, String)] = [("Nombres", "first_name", ""), ("Apellidos", "last_name", ""), ("DUI declarado", "dui", "00000000-0"),
            ("Fecha de nacimiento", "birth_date", "AAAA-MM-DD"), ("Teléfono", "phone", "0000-0000")]
            .filter { item in model.isMissing(value(of: item.1, in: person)) }
        return cardStyle {
            HStack(spacing: 12) {
                Text(initials.isEmpty ? "—" : initials).font(.headline.weight(.heavy)).foregroundStyle(.white)
                    .frame(width: 46, height: 46).background(LinearGradient.vinoDestacado, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("TUS DATOS").font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(HospitalTheme.secondary)
                    Text(name.isEmpty ? "Completa tu nombre" : name).font(.headline).foregroundStyle(HospitalTheme.ink)
                    Text("Recepción verificará tu identidad.").font(.caption).foregroundStyle(HospitalTheme.secondary)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in factView(fact.0, fact.1) }
            }
            if !model.isMissing(person.email) { factView("Correo", person.email ?? "") }
            else { Text("Tu cuenta no publica correo. Contacta al hospital.").font(.caption).foregroundStyle(HospitalTheme.secondary) }
            if !missing.isEmpty {
                Text("Completa los datos que faltan en tu cuenta:").font(.caption.weight(.bold)).foregroundStyle(HospitalTheme.wine)
                ForEach(Array(missing.enumerated()), id: \.offset) { _, item in missingField(item.0, key: item.1, placeholder: item.2) }
            }
        }
    }
    private func value(of key: String, in person: AttentionPerson) -> String? {
        switch key {
        case "first_name": return person.first_name
        case "last_name": return person.last_name
        case "dui": return person.dui
        case "birth_date": return person.birth_date
        default: return person.phone
        }
    }
    private func displayDate(_ value: String?) -> String? {
        guard let value, value.count == 10 else { return value }
        let parts = value.split(separator: "-")
        return parts.count == 3 ? "\(parts[2])/\(parts[1])/\(parts[0])" : value
    }
    private func factView(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(HospitalTheme.secondary)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(HospitalTheme.ink).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }.padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
            .background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private func missingField(_ label: String, key: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(HospitalTheme.ink)
            TextField(placeholder.isEmpty ? label : placeholder, text: Binding(
                get: { model.missing[key] ?? "" },
                set: { value in
                    if key == "dui" { model.missing[key] = ApplicantRules.shared.formatDUI(value) }
                    else if key == "phone" {
                        let digits = String(value.filter(\.isNumber).prefix(8))
                        model.missing[key] = digits.count > 4 ? String(digits.prefix(4)) + "-" + String(digits.dropFirst(4)) : digits
                    } else { model.missing[key] = value }
                }))
                .keyboardType(key == "dui" || key == "phone" ? .numberPad : key == "birth_date" ? .numbersAndPunctuation : .default)
                .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(HospitalTheme.wine.opacity(0.45), lineWidth: 1.5))
                .accessibilityLabel(label)
        }
    }

    /// Paso 1: síntomas, selección múltiple.
    private func symptomsCard(_ context: AttentionContext) -> some View {
        let count = model.selectedSymptoms.count
        return cardStyle {
            stepHeader("1", "¿Qué síntomas presentas?", "Selecciona todos los que apliquen.",
                count: count == 0 ? "Elige al menos uno" : count == 1 ? "1 elegido" : "\(count) elegidos", highlighted: count > 0)
            if context.symptoms.isEmpty {
                Text("No hay síntomas activos en el catálogo. Contacta a recepción.").font(.caption).foregroundStyle(HospitalTheme.secondary)
            }
            ConsultationFlowLayout(spacing: 8) {
                ForEach(context.symptoms) { symptom in
                    let selected = model.selectedSymptoms.contains(symptom.id)
                    Button {
                        if selected { model.selectedSymptoms.remove(symptom.id) } else { model.selectedSymptoms.insert(symptom.id) }
                    } label: {
                        HStack(spacing: 5) {
                            if selected { Image(systemName: "checkmark").font(.caption.weight(.heavy)) }
                            Text(symptom.name).font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(selected ? .white : HospitalTheme.ink)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(selected ? AnyShapeStyle(HospitalTheme.wine) : AnyShapeStyle(Color.white), in: Capsule())
                        .overlay(Capsule().stroke(selected ? HospitalTheme.wine : HospitalTheme.rose, lineWidth: 1.5))
                    }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            if model.needsOtherDescription {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Describe el otro síntoma").font(.caption.weight(.semibold))
                    TextField("Describe el otro síntoma", text: $model.otherSymptoms, axis: .vertical)
                        .lineLimit(2...5).padding(12).background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel("Otro síntoma")
                    HStack { Spacer(); Text("\(model.otherSymptoms.count) / 1000").font(.caption2).foregroundStyle(HospitalTheme.secondary) }
                }
            }
        }
    }

    /// Paso 2: especialidad en tarjetas de dos columnas; las que no tienen médico activo se muestran desactivadas.
    private func specialtyCard(_ context: AttentionContext) -> some View {
        cardStyle {
            stepHeader("2", "Especialidad", "Elige el área que mejor corresponde a tu malestar.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(context.specialties) { specialty in
                    let selected = model.specialty == specialty.id
                    Button { model.specialty = specialty.id } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(specialty.name).font(.subheadline.weight(.bold)).multilineTextAlignment(.leading)
                            if !specialty.available { Text("Sin médico disponible").font(.caption2) }
                        }
                        .foregroundStyle(!specialty.available ? HospitalTheme.secondary : selected ? HospitalTheme.wine : HospitalTheme.ink)
                        .padding(12).frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .background(!specialty.available ? HospitalTheme.background : selected ? HospitalTheme.rose : Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(selected ? HospitalTheme.wine : HospitalTheme.rose, style: StrokeStyle(lineWidth: selected ? 2 : 1.5, dash: specialty.available ? [] : [4])))
                    }
                    .buttonStyle(.plain).disabled(!specialty.available)
                    .accessibilityLabel("Especialidad médica: \(specialty.name)\(specialty.available ? "" : ", sin médico disponible")")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Text(context.specialties.contains(where: \.available) ? "Elegir una especialidad no reserva una cita: recepción confirma la disponibilidad real."
                 : "No hay especialidades con médico activo asignado. Contacta a recepción.")
                .font(.caption).foregroundStyle(HospitalTheme.secondary)
        }
    }

    /// Paso 3: preferencia de horario y motivo.
    private func detailsCard(_ context: AttentionContext) -> some View {
        cardStyle {
            stepHeader("3", "Detalles de tu solicitud", nil)
            Text("Preferencia de horario").font(.caption.weight(.bold)).foregroundStyle(HospitalTheme.ink)
            Picker("Preferencia de horario", selection: $model.preferredPeriod) {
                Text("Mañana").tag("manana")
                Text("Tarde").tag("tarde")
                Text("Indiferente").tag("indiferente")
            }.pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 6) {
                Text("Motivo de solicitud").font(.caption.weight(.bold)).foregroundStyle(HospitalTheme.ink)
                TextField("Describe brevemente qué te ocurre y desde cuándo.", text: $model.reason, axis: .vertical)
                    .lineLimit(4...8).padding(14).frame(minHeight: 104, alignment: .topLeading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(HospitalTheme.rose, lineWidth: 1.5))
                    .accessibilityLabel("Motivo de solicitud")
                HStack { Spacer(); Text("\(model.reason.count) / 2000").font(.caption2).foregroundStyle(HospitalTheme.secondary) }
            }
            if let validation = model.validationError {
                Label(validation, systemImage: "info.circle").font(.footnote.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Button { Task { await model.submit() } } label: {
                HStack(spacing: 10) {
                    if model.saving { ProgressView().tint(.white) } else { Image(systemName: "paperplane.fill") }
                    Text(model.saving ? "Enviando…" : "Solicitar atención").font(.headline)
                }.foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 54)
                    .background(LinearGradient.vinoDestacado, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .opacity(model.canSubmit ? 1 : 0.55)
            }.buttonStyle(.plain).disabled(!model.canSubmit)
            Text("Enviar no crea un expediente ni una cita. Recepción revisará tu solicitud.")
                .font(.caption).foregroundStyle(HospitalTheme.secondary).frame(maxWidth: .infinity).multilineTextAlignment(.center)
        }
    }
    /// Solo la solicitud más reciente; las anteriores siguen disponibles en una hoja aparte, sin mezclarse con el formulario.
    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tu solicitud reciente").font(.headline)
                Spacer()
            }
            if let request = model.requests.first {
                requestSummary(request)
                if model.requests.count > 1 {
                    Button { showPreviousRequests = true } label: {
                        Label("Ver solicitudes anteriores (\(model.requests.count - 1))", systemImage: "clock.arrow.circlepath").font(.subheadline.weight(.semibold))
                    }.tint(HospitalTheme.wine)
                }
            } else if !model.loading && model.error == nil {
                Text("Todavía no has enviado solicitudes de atención.").font(.subheadline).foregroundStyle(HospitalTheme.secondary)
            }
        }
        .sheet(isPresented: $showPreviousRequests) {
            NavigationStack {
                ScrollView { VStack(spacing: 12) { ForEach(model.requests.dropFirst()) { requestSummary($0) } }.padding(18) }
                    .background(HospitalTheme.background)
                    .navigationTitle("Solicitudes anteriores").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { showPreviousRequests = false } } }
            }.tint(HospitalTheme.wine)
        }
    }
    private func requestSummary(_ request: AttentionRequest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.specialty_name).font(.headline)
                    Text("Enviada el \(dateLabel(request.created_at))").font(.caption).foregroundStyle(HospitalTheme.secondary)
                }
                Spacer()
                HospitalBadge(text: request.statusLabel, warning: ["pendiente", "en_revision"].contains(request.status))
            }
            Text(request.reason).font(.subheadline)
            if !request.symptoms.isEmpty {
                ConsultationFlowLayout(spacing: 6) {
                    ForEach(request.symptoms, id: \.self) { item in
                        Text(item).font(.caption.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
                            .padding(.horizontal, 10).padding(.vertical, 5).background(HospitalTheme.rose, in: Capsule())
                    }
                }
            }
            if let other = request.other_symptoms { Text("Otros: \(other)").font(.footnote) }
            Label("Preferencia: \(request.periodLabel)", systemImage: "clock").font(.footnote).foregroundStyle(HospitalTheme.secondary)
            if request.appointment_id != nil {
                Button("Ver mi cita") { navigate("appointments") }.font(.subheadline.weight(.semibold)).tint(HospitalTheme.wine)
            }
        }.modifier(ConsultationCardStyle())
    }
    private func dateLabel(_ value: String) -> String {
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: value) ?? ISO8601DateFormatter().date(from: value) else { return "Fecha no disponible" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "es_GT")
        formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
