import SwiftUI

/// Cuenta → solicitud; recepción conserva el control del expediente y la cita.
@MainActor
struct PatientAttentionLiveView: View {
    @ObservedObject var model: PatientAttentionModel
    let navigate: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HospitalNotice(text: "Este formulario no es para emergencias. Ante una emergencia, acude al servicio de urgencias. Los síntomas que declares no constituyen un diagnóstico.")
            if model.loading { ProgressView("Cargando tus datos y solicitudes…") }
            if let error = model.error {
                HospitalNotice(text: error)
                Button("Actualizar") { Task { await model.load() } }.disabled(model.saving || model.loading)
            }
            if let confirmation = model.confirmation {
                Label(confirmation, systemImage: "checkmark.circle.fill")
                    .font(.subheadline).foregroundStyle(HospitalTheme.wine)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 16))
            }
            if let context = model.context {
                personalCard(context.person)
                symptomsCard(context)
                requestCard(context)
            } else if !model.loading && model.error == nil {
                Button("Cargar formulario") { Task { await model.load() } }
            }
            history
        }
        .disabled(model.saving)
        .accessibilityIdentifier("patient-attention-form")
    }

    private func personalCard(_ person: AttentionPerson) -> some View {
        HospitalCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Tus datos", systemImage: "person.crop.circle").font(.headline)
                Text("Cargados de tu cuenta. Completa únicamente los datos que falten; recepción verificará tu identidad.")
                    .font(.footnote).foregroundStyle(HospitalTheme.secondary)
                personalField("Nombres", key: "first_name", existing: person.first_name)
                personalField("Apellidos", key: "last_name", existing: person.last_name)
                personalField("DUI declarado", key: "dui", existing: person.dui, placeholder: "00000000-0")
                personalField("Fecha de nacimiento", key: "birth_date", existing: person.birth_date, placeholder: "AAAA-MM-DD")
                personalField("Teléfono", key: "phone", existing: person.phone, placeholder: "0000-0000")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Correo de la cuenta").font(.caption).foregroundStyle(HospitalTheme.secondary)
                    Text(model.isMissing(person.email) ? "No disponible. Contacta al hospital para completar tu cuenta." : person.email ?? "")
                        .font(.subheadline).textSelection(.enabled)
                }
            }
        }
    }
    private func personalField(_ label: String, key: String, existing: String?, placeholder: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(HospitalTheme.secondary)
            if model.isMissing(existing) {
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
                    .textFieldStyle(.roundedBorder).accessibilityLabel(label)
            } else {
                Text(existing ?? "").font(.subheadline).textSelection(.enabled)
            }
        }
    }
    private func symptomsCard(_ context: AttentionContext) -> some View {
        HospitalCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("¿Qué síntomas presentas?", systemImage: "heart.text.square").font(.headline)
                Text("Selecciona uno o varios síntomas declarados.").font(.footnote).foregroundStyle(HospitalTheme.secondary)
                if context.symptoms.isEmpty {
                    Text("El hospital todavía no tiene síntomas activos en el catálogo. Contacta a recepción.")
                        .font(.subheadline)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), alignment: .leading)], alignment: .leading, spacing: 10) {
                    ForEach(context.symptoms) { symptom in
                        let selected = model.selectedSymptoms.contains(symptom.id)
                        Button {
                            if selected { model.selectedSymptoms.remove(symptom.id) }
                            else { model.selectedSymptoms.insert(symptom.id) }
                        } label: {
                            Label(symptom.name, systemImage: selected ? "checkmark.circle.fill" : "circle")
                                .font(.subheadline).multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(10)
                                .background(selected ? HospitalTheme.rose : HospitalTheme.background, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).foregroundStyle(HospitalTheme.wine)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                if model.needsOtherDescription {
                    TextField("Describe el otro síntoma", text: $model.otherSymptoms, axis: .vertical)
                        .lineLimit(2...5).textFieldStyle(.roundedBorder).accessibilityLabel("Otro síntoma")
                    Text("\(model.otherSymptoms.count)/1000").font(.caption).foregroundStyle(HospitalTheme.secondary)
                }
            }
        }
    }
    private func requestCard(_ context: AttentionContext) -> some View {
        HospitalCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Tu solicitud", systemImage: "cross.case").font(.headline)
                if context.specialties.contains(where: \.available) {
                    Picker("Especialidad médica", selection: $model.specialty) {
                        Text("Seleccionar").tag(nil as Int64?)
                        ForEach(context.specialties.filter(\.available)) { specialty in
                            Text(specialty.name).tag(Optional(specialty.id))
                        }
                    }.pickerStyle(.menu)
                    Text("Las especialidades seleccionables tienen médico activo asignado. Recepción revisará la disponibilidad real; no estás eligiendo una cita.")
                        .font(.footnote).foregroundStyle(HospitalTheme.secondary)
                } else {
                    Text("No hay especialidades con médicos activos asignados. Contacta a recepción para solicitar orientación.")
                        .font(.subheadline)
                }
                ForEach(context.specialties.filter { !$0.available }) { specialty in
                    Text("\(specialty.name) · Sin médico activo asignado")
                        .font(.caption).foregroundStyle(HospitalTheme.secondary)
                }
                Picker("Preferencia de horario", selection: $model.preferredPeriod) {
                    Text("Mañana").tag("manana")
                    Text("Tarde").tag("tarde")
                    Text("Indiferente").tag("indiferente")
                }.pickerStyle(.menu)
                TextField("Motivo de solicitud (obligatorio)", text: $model.reason, axis: .vertical)
                    .lineLimit(3...7).textFieldStyle(.roundedBorder).accessibilityLabel("Motivo de solicitud")
                Text("\(model.reason.count)/2000").font(.caption).foregroundStyle(HospitalTheme.secondary)
                if let validation = model.validationError {
                    Text(validation).font(.footnote).foregroundStyle(HospitalTheme.secondary)
                }
                Button { Task { await model.submit() } } label: {
                    HStack { if model.saving { ProgressView().tint(.white) }; Text(model.saving ? "Enviando…" : "Solicitar atención") }
                }.buttonStyle(HospitalPrimaryButtonStyle()).disabled(!model.canSubmit)
                Text("Recepción recibe la solicitud y gestiona tu expediente y tu cita cuando corresponda. Enviar no crea ninguno de ellos.")
                    .font(.footnote).foregroundStyle(HospitalTheme.secondary)
            }
        }
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mis solicitudes").font(.headline)
                Spacer()
                Button("Actualizar") { Task { await model.load() } }.font(.footnote).disabled(model.loading || model.saving)
            }
            if model.requests.isEmpty && !model.loading && model.error == nil {
                HospitalCard { Text("Todavía no has enviado solicitudes de atención.").font(.subheadline).foregroundStyle(HospitalTheme.secondary) }
            }
            ForEach(model.requests) { request in
                HospitalCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            Text(request.specialty_name).font(.headline)
                            Spacer()
                            HospitalBadge(text: request.statusLabel, warning: ["pendiente", "en_revision"].contains(request.status))
                        }
                        Text(dateLabel(request.created_at)).font(.caption).foregroundStyle(HospitalTheme.secondary)
                        Text(request.reason).font(.subheadline)
                        Text(request.symptoms.joined(separator: " · ")).font(.footnote).foregroundStyle(HospitalTheme.secondary)
                        if let other = request.other_symptoms { Text(other).font(.footnote) }
                        Text("Preferencia: \(request.periodLabel)").font(.footnote)
                        if request.appointment_id != nil {
                            Button("Ver mi cita") { navigate("appointments") }.font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
        }
    }
    private func dateLabel(_ value: String) -> String {
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: value) ?? ISO8601DateFormatter().date(from: value) else { return "Fecha no disponible" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "es_GT")
        formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
