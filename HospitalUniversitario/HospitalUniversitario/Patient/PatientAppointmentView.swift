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

/// Pantalla de Agendar cita: datos del paciente editables, síntomas frecuentes,
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
                    Picker("Preferencia de horario", selection: $preference) {
                        Text("Seleccionar").tag(""); Text("Mañana").tag("Mañana"); Text("Tarde").tag("Tarde")
                    }.pickerStyle(.segmented)
                    Text("Recepción confirmará fecha y hora. Los horarios mostrados son orientativos.").font(.caption).foregroundStyle(HospitalTheme.secondary)
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
