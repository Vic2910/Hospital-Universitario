import SwiftUI

/// Horario de prueba de una especialidad.
struct HorarioCita: Identifiable, Equatable {
    let id = UUID()
    let dia: String
    let hora: String
}

/// Especialidad de prueba con sus horarios disponibles precargados.
/// La base de datos aún no publica horarios reales para el paciente.
struct EspecialidadCita: Identifiable {
    let id = UUID()
    let nombre: String
    let icono: String
    let horarios: [HorarioCita]
}

/// Datos de un paciente de prueba precargados en el código.
/// La base de datos todavía no devuelve estos campos en el cliente.
enum PatientTestRecord {
    static let nombres = "Gaby"
    static let apellidos = "Diaz"
    static let dui = "0123-45678"
    static let telefono = "7123-4567"
    static let correo = "gaby.diaz@ejemplo.test"
}

/// Solicitud de atención conectada a Supabase.
/// Usa el catálogo de especialidades publicado por el hospital (`mobile_module('request')`),
/// los datos del perfil en solo lectura y envía la solicitud con `request_appointment`.
/// La fecha y la preferencia (Mañana 08:00–12:00 / Tarde 13:00–17:00) son preferencias:
/// la disponibilidad exacta la confirma recepción.
struct PatientAppointmentRealView: View {
    @ObservedObject var model: MobileModuleViewModel
    let profile: UserProfile?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sintomas: Set<String> = []
    @State private var preference = ""

    static let sintomasComunes = ["Sangrado", "Tos", "Hueso roto", "Fiebre", "Dolor de cabeza",
                                  "Náuseas", "Falta de aire", "Dolor abdominal", "Mareo", "Dolor articular"]
    static let ninguno = "Ninguno"

    private static var manana: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    private var catalogo: [MobileOption] { (model.page?.options ?? []).filter { $0.kind == "specialty" } }

    /// Validación del modo real: especialidad del catálogo, fecha desde mañana, preferencia y motivo.
    private var puedeAgendar: Bool {
        !model.saving && model.specialty != nil
            && MobileFormatting.day(model.preferredDay) >= MobileFormatting.day(Self.manana)
            && ["Mañana", "Tarde"].contains(preference)
            && !model.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Traduce la preferencia a la franja horaria que espera `request_appointment`.
    private func aplicarPreferencia() {
        let day = model.preferredDay
        if preference == "Mañana" {
            model.preferredFrom = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: day) ?? model.preferredFrom
            model.preferredTo = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? model.preferredTo
        } else if preference == "Tarde" {
            model.preferredFrom = Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: day) ?? model.preferredFrom
            model.preferredTo = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: day) ?? model.preferredTo
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("TU SALUD, A TU TIEMPO").font(.system(size: 10, weight: .bold)).tracking(1.4)
                Text("Preparemos tu próxima cita").font(.system(size: 24, weight: .bold))
                Text("Completa tus datos, cuéntanos cómo te sientes y elige tu atención.").font(.system(size: 13))
                Text("La solicitud se envía a la central de citas del hospital.").font(.system(size: 10))
            }
            .foregroundStyle(.white)
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient.vinoDestacado, in: RoundedRectangle(cornerRadius: 22))

            PatientFormCard(titulo: "Datos del paciente", icono: "person") {
                Text("Datos de tu perfil del hospital. Para actualizarlos usa «Perfil».")
                    .font(.footnote).foregroundStyle(HospitalTheme.secondary)
                DoctorConsultationField(label: "Nombres y apellidos", value: nombreReal)
                DoctorConsultationField(label: "Correo electrónico", value: profile?.auth_email ?? "No registrado")
                DoctorConsultationField(label: "Teléfono", value: telefonoReal)
            }

            PatientFormCard(titulo: "Síntomas frecuentes", icono: "heart.text.square") {
                Text("Se añadirán al motivo de la consulta. Puedes elegir varios.").font(.footnote).foregroundStyle(HospitalTheme.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                    ForEach(Self.sintomasComunes + [Self.ninguno], id: \.self) { sintoma in
                        PatientSelectChip(texto: sintoma, seleccionado: sintomas.contains(sintoma)) {
                            seleccionarSintoma(sintoma)
                        }
                    }
                }
            }

            PatientFormCard(titulo: "Motivo de consulta", icono: "text.alignleft") {
                TextEditor(text: $model.reason)
                    .accessibilityLabel("Motivo de consulta")
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 100)
                    .background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topLeading) {
                        if model.reason.isEmpty {
                            Text("Describe con tus palabras lo que te pasa…")
                                .font(.system(size: 14)).foregroundStyle(HospitalTheme.secondary)
                                .padding(18).allowsHitTesting(false)
                        }
                    }
            }

            PatientFormCard(titulo: "Tipo de doctor", icono: "stethoscope") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                    ForEach(catalogo) { item in
                        PatientSelectChip(texto: item.name, seleccionado: model.specialty == item.id) {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                                model.specialty = model.specialty == item.id ? nil : item.id
                            }
                        }
                    }
                }
                if catalogo.isEmpty {
                    Text("No hay especialidades publicadas por el hospital.")
                        .font(.footnote).foregroundStyle(HospitalTheme.secondary)
                } else {
                    Text("La disponibilidad exacta la confirma recepción.").font(.caption).foregroundStyle(HospitalTheme.secondary)
                }
            }

            PatientFormCard(titulo: "Fecha preferida", icono: "calendar") {
                DatePicker("Fecha de la atención", selection: $model.preferredDay, in: Self.manana..., displayedComponents: .date)
                    .tint(HospitalTheme.wine)
                Text("La fecha es una preferencia; recepción confirmará la disponibilidad.")
                    .font(.caption).foregroundStyle(HospitalTheme.secondary)
            }

            PatientFormCard(titulo: "Preferencia de horario", icono: "sun.max") {
                HStack(spacing: 12) {
                    PatientTimePreferenceCard(title: "Mañana", period: "AM", icon: "sun.max", selected: preference == "Mañana") { preference = "Mañana" }
                    PatientTimePreferenceCard(title: "Tarde", period: "PM", icon: "sun.haze", selected: preference == "Tarde") { preference = "Tarde" }
                }
                Text("Mañana equivale a 08:00–12:00 y Tarde a 13:00–17:00; la hora exacta la confirma recepción.")
                    .font(.caption).foregroundStyle(HospitalTheme.secondary)
            }

            PatientFormCard(titulo: "Tu selección", icono: "calendar") {
                Text(resumen).font(.subheadline)
                Text("La solicitud queda pendiente de confirmación por la central de citas.")
                    .font(.footnote).foregroundStyle(HospitalTheme.secondary)
            }

            if let confirmation = model.confirmation {
                Text(confirmation).font(.footnote).foregroundStyle(HospitalTheme.wine)
            }
            if let error = model.error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }

            Button {
                guard puedeAgendar else { return }
                model.symptoms = sintomas.contains(Self.ninguno) ? [] : sintomas.sorted()
                aplicarPreferencia()
                Task { await model.requestAppointment() }
            } label: { Text("Solicitar atención") }
                .buttonStyle(HospitalPrimaryButtonStyle())
                .disabled(!puedeAgendar)

            PatientFormCard(titulo: "Mis solicitudes", icono: "clock") {
                Text("Recepción debe asignar la cita. La preferencia no confirma disponibilidad.")
                    .font(.caption).foregroundStyle(HospitalTheme.secondary)
                if model.items.isEmpty {
                    Text("Todavía no tienes solicitudes registradas.").font(.footnote).foregroundStyle(HospitalTheme.secondary)
                }
                ForEach(model.items) { item in
                    HospitalCard {
                        Text(item.title).font(.subheadline.weight(.semibold))
                        HospitalBadge(text: MobileFormatting.status(item.status), warning: item.status == "pending")
                        if let subtitle = item.subtitle { Text(subtitle).font(.footnote) }
                        Text(DoctorDate.display(item.event_at)).font(.caption)
                        DisclosureGroup("Ver detalle") {
                            ForEach(Array(item.details.enumerated()), id: \.offset) { _, field in
                                DoctorConsultationField(label: field.label, value: field.value)
                            }
                        }.font(.footnote)
                    }
                }
            }
        }
        .onChange(of: preference) { _, _ in aplicarPreferencia() }
        .onChange(of: model.preferredDay) { _, _ in aplicarPreferencia() }
        .scrollDismissesKeyboard(.interactively)
    }

    private var nombreReal: String {
        let given = profile?.person?.given_names.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let family = profile?.person?.family_names.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let full = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? "No hay datos reales" : full
    }

    private var telefonoReal: String {
        let phone = profile?.contacts.first { $0.kind == "phone" }?.value ?? ""
        return phone.isEmpty ? "No registrado" : phone
    }

    private var resumen: String {
        guard let id = model.specialty, let nombre = catalogo.first(where: { $0.id == id })?.name else {
            return "Elige una especialidad, una fecha y una preferencia horaria para continuar."
        }
        return "\(nombre) · \(MobileFormatting.day(model.preferredDay)) · \(preference.isEmpty ? "Preferencia por definir" : preference)"
    }

    /// Selección múltiple de síntomas; «Ninguno» excluye a los demás.
    private func seleccionarSintoma(_ valor: String) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            if valor == Self.ninguno {
                sintomas = [Self.ninguno]
            } else {
                sintomas.remove(Self.ninguno)
                if sintomas.contains(valor) { sintomas.remove(valor) } else { sintomas.insert(valor) }
            }
        }
    }
}

/// Pantalla de Agendar cita en modo local: datos del paciente editables, síntomas frecuentes,
/// motivo de consulta, especialidad y horarios de prueba.
/// Es una vista de presentación: no escribe en la base de datos.
struct PatientAppointmentView: View {
    @ObservedObject var flow: PatientAppointmentFlowStore
    @State private var preference = ""
    @State private var requestKey = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nombres = PatientTestRecord.nombres
    @State private var apellidos = PatientTestRecord.apellidos
    @State private var dui = PatientTestRecord.dui
    @State private var telefono = PatientTestRecord.telefono
    @State private var correo = PatientTestRecord.correo
    @State private var sintomas: Set<String> = []
    @State private var motivo = ""
    @State private var especialidad: EspecialidadCita?
    @State private var horario: HorarioCita?
    @State private var confirmada = false

    static let sintomasComunes = ["Sangrado", "Tos", "Hueso roto", "Fiebre", "Dolor de cabeza",
                                  "Náuseas", "Falta de aire", "Dolor abdominal", "Mareo", "Dolor articular"]
    static let ninguno = "Ninguno"

    /// Especialidades y horarios de prueba, precargados en el código.
    static let especialidades: [EspecialidadCita] = [
        EspecialidadCita(nombre: "Médico general", icono: "stethoscope", horarios: [
            HorarioCita(dia: "Hoy", hora: "2:00 pm – 4:00 pm"),
            HorarioCita(dia: "Mañana", hora: "8:00 am – 10:00 am"),
            HorarioCita(dia: "Lunes", hora: "10:00 am – 12:00 m")]),
        EspecialidadCita(nombre: "Cardiólogo", icono: "heart", horarios: [
            HorarioCita(dia: "Mañana", hora: "9:00 am – 11:00 am"),
            HorarioCita(dia: "Martes", hora: "3:00 pm – 5:00 pm")]),
        EspecialidadCita(nombre: "Neurólogo", icono: "brain.head.profile", horarios: [
            HorarioCita(dia: "Martes", hora: "8:00 am – 10:00 am"),
            HorarioCita(dia: "Jueves", hora: "1:00 pm – 3:00 pm")]),
        EspecialidadCita(nombre: "Ortopedista", icono: "figure.walk", horarios: [
            HorarioCita(dia: "Hoy", hora: "4:30 pm – 6:00 pm"),
            HorarioCita(dia: "Miércoles", hora: "9:00 am – 11:00 am")]),
        EspecialidadCita(nombre: "Cirujano", icono: "cross.fill", horarios: [
            HorarioCita(dia: "Jueves", hora: "10:00 am – 12:00 m"),
            HorarioCita(dia: "Viernes", hora: "8:00 am – 9:30 am")]),
        EspecialidadCita(nombre: "Pediatra", icono: "figure.and.child.holdinghands", horarios: [
            HorarioCita(dia: "Mañana", hora: "11:00 am – 1:00 pm"),
            HorarioCita(dia: "Sábado", hora: "9:00 am – 11:00 am")])
    ]

    /// Valida los datos editables, el motivo y la selección de atención.
    private var puedeAgendar: Bool {
        especialidad != nil && horario != nil && !preference.isEmpty && !motivo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !nombres.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !apellidos.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && dui.trimmingCharacters(in: .whitespacesAndNewlines).range(of: #"^\d{4}-\d{5}$"#, options: .regularExpression) != nil
        && telefono.trimmingCharacters(in: .whitespacesAndNewlines).range(of: #"^\d{4}-\d{4}$"#, options: .regularExpression) != nil
        && correo.trimmingCharacters(in: .whitespacesAndNewlines).range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("TU SALUD, A TU TIEMPO").font(.system(size: 10, weight: .bold)).tracking(1.4)
                    Text("Preparemos tu próxima cita").font(.system(size: 24, weight: .bold))
                    Text("Completa tus datos, cuéntanos cómo te sientes y elige tu atención.").font(.system(size: 13))
                    Text("Paciente y horarios de prueba · No se envía al hospital").font(.system(size: 10))
                }
                .foregroundStyle(.white)
                .padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient.vinoDestacado, in: RoundedRectangle(cornerRadius: 22))
                PatientFormCard(titulo: "Datos del paciente", icono: "person") {
                    Text("Datos de prueba. Puedes editarlos para agendar para otra persona.")
                        .font(.footnote).foregroundStyle(HospitalTheme.secondary)
                    HospitalInputField(label: "Nombres", placeholder: "Nombres", text: $nombres)
                    HospitalInputField(label: "Apellidos", placeholder: "Apellidos", text: $apellidos)
                    HospitalInputField(label: "DUI", placeholder: "0000-00000", text: $dui, keyboard: .numbersAndPunctuation)
                    HospitalInputField(label: "Teléfono", placeholder: "0000-0000", text: $telefono, keyboard: .phonePad)
                    HospitalInputField(label: "Correo electrónico", placeholder: "nombre@correo.com", text: $correo,
                                       keyboard: .emailAddress, contentType: .username, autocapitalization: .never)
                }

                PatientFormCard(titulo: "Síntomas frecuentes", icono: "heart.text.square") {
                    Text("Selecciona lo que te aplica. Puedes elegir varios.").font(.footnote).foregroundStyle(HospitalTheme.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                        ForEach(Self.sintomasComunes + [Self.ninguno], id: \.self) { sintoma in
                            PatientSelectChip(texto: sintoma, seleccionado: sintomas.contains(sintoma)) {
                                seleccionarSintoma(sintoma)
                            }
                        }
                    }
                }

                PatientFormCard(titulo: "Motivo de consulta", icono: "text.alignleft") {
                    TextEditor(text: $motivo)
                        .accessibilityLabel("Motivo de consulta")
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 100)
                        .background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(alignment: .topLeading) {
                            if motivo.isEmpty {
                                Text("Describe con tus palabras lo que te pasa…")
                                    .font(.system(size: 14)).foregroundStyle(HospitalTheme.secondary)
                                    .padding(18).allowsHitTesting(false)
                            }
                        }
                }

                PatientFormCard(titulo: "Tipo de doctor", icono: "stethoscope") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                        ForEach(Self.especialidades) { item in
                            PatientSelectChip(texto: item.nombre, seleccionado: especialidad?.id == item.id) {
                                seleccionarEspecialidad(item)
                            }
                        }
                    }
                    if let especialidad {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Horarios orientativos").font(.system(size: 13, weight: .semibold)).foregroundStyle(HospitalTheme.ink)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                                ForEach(especialidad.horarios) { slot in
                                    PatientSlotChip(dia: slot.dia, hora: slot.hora, seleccionado: horario?.id == slot.id) {
                                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { horario = slot; confirmada = false }
                                    }
                                }
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        Text("Selecciona una especialidad para ver los horarios.")
                            .font(.footnote).foregroundStyle(HospitalTheme.secondary)
                    }
                }

                PatientFormCard(titulo: "Preferencia de horario", icono: "sun.max") {
                    HStack(spacing: 12) {
                        PatientTimePreferenceCard(title: "Mañana", period: "AM", icon: "sun.max", selected: preference == "Mañana") { preference = "Mañana" }
                        PatientTimePreferenceCard(title: "Tarde", period: "PM", icon: "sun.haze", selected: preference == "Tarde") { preference = "Tarde" }
                    }
                    Text("Selecciona la opción que te convenga. Recepción confirmará la fecha y hora.").font(.caption).foregroundStyle(HospitalTheme.secondary)
                }
                PatientFormCard(titulo: "Tu selección", icono: "calendar") {
                    if let especialidad, let horario {
                        Text("\(especialidad.nombre) · \(horario.dia) · \(horario.hora)").font(.subheadline)
                    } else {
                        Text("Elige una especialidad y un horario para continuar.").font(.subheadline)
                    }
                    Text("Completa todos los campos. DUI: 0000-00000; teléfono: 0000-0000; correo válido.")
                        .font(.footnote).foregroundStyle(HospitalTheme.secondary)
                }

                if let especialidad, let horario, confirmada {
                    PatientScheduleSuccess(especialidad: especialidad.nombre, horario: "\(horario.dia) · \(horario.hora)")
                }

                Button {
                    guard puedeAgendar, !confirmada, let especialidad, let horario else { return }
                    let request = PatientAttentionRequest(id: requestKey, createdAt: Date(), givenName: nombres, familyName: apellidos, dui: dui, phone: telefono, email: correo, specialty: especialidad.nombre,
                        reason: motivo, symptoms: sintomas.sorted(), preference: preference, preferredSlot: horario.dia + " · " + horario.hora)
                    if flow.submit(request) { withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) { confirmada = true }; requestKey = UUID() }
                } label: { Text("Solicitar atención") }
                    .buttonStyle(HospitalPrimaryButtonStyle())
                    .disabled(!puedeAgendar || confirmada)
                DisclosureGroup("Mis solicitudes de ejemplo") {
                    ForEach(flow.requests) { request in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(request.specialty).font(.subheadline.weight(.semibold))
                            HospitalBadge(text: request.state.label, warning: request.state == .pending)
                            Text(request.reason).font(.footnote)
                            Text("Preferencia: " + request.preference).font(.caption)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                    }
                }.font(.subheadline).tint(HospitalTheme.wine)

            }

        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: [nombres, apellidos, dui, telefono, correo, motivo, preference]) { _, _ in confirmada = false }
    }

    /// Selección múltiple de síntomas; «Ninguno» excluye a los demás.
    private func seleccionarSintoma(_ valor: String) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            confirmada = false
            if valor == Self.ninguno {
                sintomas = [Self.ninguno]
            } else {
                sintomas.remove(Self.ninguno)
                if sintomas.contains(valor) { sintomas.remove(valor) } else { sintomas.insert(valor) }
            }
        }
    }

    /// Selección única de especialidad; cambiarla limpia el horario elegido.
    private func seleccionarEspecialidad(_ item: EspecialidadCita) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            confirmada = false
            if especialidad?.id == item.id { especialidad = nil; horario = nil }
            else { especialidad = item; horario = nil }
        }
    }
}

#Preview {
    ScrollView { PatientAppointmentView(flow: PatientAppointmentFlowStore()).padding(17) }
        .background(Color.fondoApp)
        .preferredColorScheme(.light)
}
