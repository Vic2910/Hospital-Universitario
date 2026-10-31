import SwiftUI

/// Connected clinical screens. The design fixture store is never used in a session.
@MainActor
struct DoctorClinicalView: View {
    @ObservedObject var model: DoctorViewModel
    let screenID: String
    let navigate: (String) -> Void
    let period: (String) -> String
    @State private var query = ""
    @State private var stage = ""
    @State private var selectedLabID: UUID?

    private var labs: [DoctorChartLab] {
        (model.chart?.laboratories ?? []).sorted { $0.requested_at > $1.requested_at }
    }
    private var lab: DoctorChartLab? { labs.first { $0.id == selectedLabID } }
    private var patient: DoctorPatientChart.Patient? { model.chart?.patient }
    private var age: String {
        guard let value = patient?.birth_date else { return "No registrado" }
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        guard let birth = formatter.date(from: value), let years = Calendar.current.dateComponents([.year], from: birth, to: Date()).year, years >= 0 else { return "No registrado" }
        return "\(years) años"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if stage.isEmpty || model.selectedAppointment == nil { landing }
            else {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Button("Volver") { if selectedLabID != nil { selectedLabID = nil } else { stage = "" } }
                        Spacer()
                        Text("FICHA CLÍNICA").font(.caption).foregroundStyle(HospitalTheme.secondary)
                    }
                    Text(lab != nil ? "Detalle de examen" : stage == "request" ? "Solicitar exámenes" : "Expediente completo")
                        .font(.system(size: 27, weight: .bold)).accessibilityAddTraits(.isHeader)
                    if let patient {
                        if lab != nil {
                            PatientFormCard(titulo: "Paciente", icono: "person") {
                                field("Nombre completo", patient.full_name)
                                HStack { field("Edad", age); Spacer(); field("Teléfono", patient.phone) }
                            }
                        } else {
                            PatientFormCard(titulo: "Datos personales", icono: "person") {
                                ClinicalPatientIdentityView(givenName: patient.given_names ?? "", familyName: patient.family_names ?? "",
                                    fullName: patient.full_name, age: age, dui: patient.dui ?? patient.identification ?? "",
                                    email: patient.email ?? "", phone: patient.phone ?? "", record: patient.record_number)
                            }
                        }
                        if stage == "request" { requestForm }
                        else if let lab { labDetail(lab) }
                        else { record }
                    } else if !model.loadingChart {
                        Text("No se pudo cargar el expediente.")
                        Button("Reintentar") { Task { await model.loadChart() } }
                        Button("Ir a consulta") { navigate("consultation") }
                    }
                }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(HospitalTheme.rose, lineWidth: 1))
            }
        }
        .onChange(of: screenID) { _, _ in stage = ""; selectedLabID = nil }
        .onChange(of: model.selectedAppointmentID) { _, _ in selectedLabID = nil }
    }

    private var landing: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(screenID == "patients" ? "TU PRÁCTICA MÉDICA" : "ATENCIÓN CLÍNICA").font(.caption.weight(.bold))
                Text(screenID == "patients" ? "Tus pacientes, su evolución" : screenID == "laboratory" ? "Laboratorio, paso a paso" : "Un expediente, toda la información")
                    .font(.system(size: 24, weight: .bold))
                Text("Busca un paciente de tu agenda para consultar su información autorizada.").font(.footnote)
            }.foregroundStyle(.white).padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient.vinoDestacado, in: RoundedRectangle(cornerRadius: 22))
            PatientFormCard(titulo: "Buscar paciente", icono: "magnifyingglass") {
                TextField("DUI o nombre del paciente", text: $query).textFieldStyle(.roundedBorder)
                DatePicker("Fecha de atención", selection: $model.day, displayedComponents: .date)
                    .onChange(of: model.day) { _, _ in model.select(nil); stage = ""; Task { await model.refresh() } }
                let matches = (model.workspace?.appointments ?? []).filter {
                    query.isEmpty || ($0.patient_name + " " + ($0.dui ?? "") + " " + $0.record_number)
                        .replacingOccurrences(of: "-", with: "").localizedStandardContains(query.replacingOccurrences(of: "-", with: ""))
                }
                if matches.isEmpty { Text("No hay pacientes asignados que coincidan para esta fecha.").font(.footnote) }
                ForEach(matches) { item in
                    Button {
                        model.select(item.id)
                        stage = screenID == "laboratory" ? "" : "record"
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.patient_name).font(.headline)
                            Text("DUI: \(item.dui ?? "No registrado") · \(item.record_number)").font(.caption)
                            Text(period(item.period)).font(.caption)
                            Text("Ver ficha e historial").font(.caption.weight(.bold))
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                            .background(.white, in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(HospitalTheme.wine.opacity(0.14), lineWidth: 1))
                    }.buttonStyle(.plain).accessibilityLabel("Seleccionar a \(item.patient_name)")
                }
            }
            if let appointment = model.selectedAppointment {
                PatientFormCard(titulo: appointment.patient_name, icono: "person.text.rectangle") {
                    Text(appointment.record_number).font(.footnote)
                    Button(screenID == "laboratory" ? "Solicitar exámenes" : "Abrir expediente completo") {
                        stage = screenID == "laboratory" ? "request" : "record"
                        Task { await model.loadChart() }
                    }.buttonStyle(HospitalPrimaryButtonStyle())
                }
            }
        }
    }

    private var requestForm: some View {
        PatientFormCard(titulo: "Solicitud de laboratorio", icono: "testtube.2") {
            field("Clínica", model.workspace?.facility_name)
            field("Médico emisor", model.workspace?.doctor_name)
            if model.canEditConsultation {
                Picker("Tipo de laboratorio", selection: $model.selectedTestID) {
                    Text("Seleccionar estudio").tag(nil as UUID?)
                    ForEach(model.workspace?.tests ?? []) { item in Text(item.name).tag(Optional(item.id)) }
                }
                if model.workspace?.tests.isEmpty == true { Text("No hay estudios activos en el catálogo.").font(.footnote) }
                TextField("Indicaciones u observaciones", text: $model.instructions, axis: .vertical).lineLimit(3...6)
                TextField("Peso (kg)", text: $model.weight).keyboardType(.decimalPad)
                TextField("Altura (cm)", text: $model.height).keyboardType(.decimalPad)
                Button("Emitir orden") { Task { await model.issueOrder() } }
                    .buttonStyle(HospitalPrimaryButtonStyle())
                    .disabled(model.selectedTestID == nil || model.instructions.count > 10000 || !model.validMeasurements)
            } else {
                Text("La emisión requiere una consulta abierta de este paciente.").font(.footnote)
                Button("Ir a consulta") { navigate("consultation") }
            }
        }
    }

    private var record: some View {
        VStack(alignment: .leading, spacing: 18) {
            PatientFormCard(titulo: "Historial clínico de mis consultas", icono: "clock.arrow.circlepath") {
                if model.chart?.history.isEmpty != false { Text("Sin consultas previas registradas.").font(.footnote) }
                ForEach(model.chart?.history ?? []) { visit in
                    HospitalCard {
                        Text(DoctorDate.display(visit.started_at)).font(.headline)
                        field("Motivo", visit.subjective); field("Exploración", visit.objective)
                        field("Evaluación", visit.assessment); field("Plan", visit.plan)
                    }
                }
            }
            PatientFormCard(titulo: "Notas y recetas", icono: "doc.text") {
                if let chart = model.chart {
                    field("Alergias", chart.allergies.isEmpty ? "Sin registros" : chart.allergies.joined(separator: "\n"))
                    field("Condiciones", chart.conditions.isEmpty ? "Sin registros" : chart.conditions.joined(separator: "\n"))
                    field("Antecedentes", chart.medical_history?.joined(separator: "\n"))
                    field("Medicamentos", chart.medications?.joined(separator: "\n"))
                    ForEach(Array((chart.vitals ?? []).enumerated()), id: \.offset) { _, vital in field(vital.label, vital.value) }
                }
                actions
            }
            PatientFormCard(titulo: "Laboratorios del expediente", icono: "testtube.2") {
                Text("Más recientes primero · Solicitudes y resultados del paciente").font(.caption).foregroundStyle(HospitalTheme.secondary)
                if labs.isEmpty { Text("Este paciente todavía no tiene exámenes registrados.").font(.footnote) }
                ForEach(labs) { item in
                    HospitalCard {
                        Text(item.test_name).font(.headline)
                        Text(DoctorDate.display(item.requested_at)).font(.caption)
                        HospitalBadge(text: item.label, warning: !item.published)
                        Button("Ver detalle") { selectedLabID = item.id }.font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
    }

    private func labDetail(_ item: DoctorChartLab) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            PatientFormCard(titulo: item.test_name, icono: "testtube.2") {
                field("Fecha de solicitud", DoctorDate.display(item.requested_at))
                HospitalBadge(text: item.label, warning: !item.published)
                field("Indicaciones", item.instructions)
            }
            PatientFormCard(titulo: "Resultado del examen", icono: "doc.text") {
                if item.published {
                    if let narrative = item.narrative { field("Informe", narrative) }
                    ForEach(Array(item.values.enumerated()), id: \.offset) { _, value in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(value.name).font(.headline)
                            Text([value.value, value.unit].compactMap { $0 }.joined(separator: " ")).font(.title2.bold()).foregroundStyle(HospitalTheme.wine)
                            Text("Referencia: \(value.reference ?? "No registrada")").font(.caption)
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 14))
                    }
                    field("Publicado", DoctorDate.display(item.released_at))
                } else { Text(item.status == "in_progress" ? "El laboratorio está procesando el examen." : "No hay resultados publicados.").font(.footnote) }
            }
            actions
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Las observaciones y recetas se registran en la consulta abierta.").font(.caption).foregroundStyle(HospitalTheme.secondary)
            Button("Añadir observación") { navigate("consultation") }
            Button("Añadir receta") { navigate(model.canEditConsultation ? "prescriptions" : "consultation") }
        }
    }
    private func field(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(HospitalTheme.secondary)
            Text(value.flatMap { $0.isEmpty ? nil : $0 } ?? "No registrado").font(.subheadline)
        }
    }
}
