import SwiftUI

@MainActor
struct DoctorModuleView: View {
    @ObservedObject var model: DoctorViewModel
    let screenID: String
    let search: String
    let navigate: (String) -> Void
    let period: (String) -> String
    @State private var confirmClose = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.loading || model.loadingChart || model.saving {
                ProgressView(model.saving ? "Guardando…" : "Cargando…").frame(maxWidth: .infinity)
            }
            if let error = model.error {
                Text(error).font(.footnote).foregroundStyle(.red).accessibilityLabel("Error: \(error)")
                Button("Reintentar", systemImage: "arrow.clockwise") {
                    Task { await model.refresh(); await model.loadChart() }
                }
            }
            if let confirmation = model.confirmation {
                Text(confirmation).font(.footnote).foregroundStyle(HospitalTheme.wine)
            }
            if let workspace = model.workspace {
                if !["home", "notifications", "consultation"].contains(screenID) { dayPicker }
                switch screenID {
                case "home": dashboard(workspace)
                case "patients": patients(workspace)
                case "consultation": consultation(workspace)
                case "chart": patientChart(workspace)
                case "laboratory": laboratory(workspace)
                case "notifications": notifications(workspace.notifications)
                default: EmptyView()
                }
            } else if !model.loading && model.error == nil {
                empty("No hay información disponible para esta sede.")
            }
        }
        .disabled(model.saving || model.loading || model.loadingChart)
        .task(id: model.selectedAppointmentID) { await model.loadChart() }
        .confirmationDialog("¿Firmar y cerrar la consulta?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Firmar y cerrar", role: .destructive) { Task { await model.closeConsultation() } }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("La nota quedará firmada y la atención finalizará. Esta acción no puede deshacerse desde la app.")
        }
    }

    private var dayPicker: some View {
        DatePicker("Fecha de atención", selection: $model.day, displayedComponents: .date)
            .font(.subheadline)
            .onChange(of: model.day) { _, _ in
                model.select(nil)
                Task { await model.refresh() }
            }
    }

    private func dashboard(_ workspace: DoctorWorkspace) -> some View {
        DoctorDashboardView(name: workspace.doctor_name, facility: workspace.facility_name,
            consultationCount: workspace.appointments.filter { !["cancelled", "rejected", "no_show"].contains($0.status) }.count,
            navigate: navigate)
    }

    private func matches(_ text: String) -> Bool { search.isEmpty || text.localizedCaseInsensitiveContains(search) }

    private func patients(_ workspace: DoctorWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let values = workspace.appointments.filter { matches($0.patient_name + " " + $0.record_number + " " + ($0.ticket_number ?? "")) }
            if values.isEmpty { empty("No hay pacientes asignados que coincidan con la búsqueda.") }
            ForEach(values) { appointment in
                HospitalCard {
                    Text(appointment.patient_name).font(.subheadline.weight(.semibold))
                    Text("Expediente: \(appointment.record_number)").font(.caption)
                    Text("Turno: \(appointment.ticket_number ?? "Sin turno asignado")").font(.caption)
                    Text(period(appointment.period)).font(.caption).foregroundStyle(HospitalTheme.secondary)
                    HospitalBadge(text: status(appointment.status))
                    HStack {
                        Button("Atender", systemImage: "cross.case") {
                            model.select(appointment.id); navigate("consultation")
                        }
                        Spacer()
                        Button("Expediente", systemImage: "doc.text") {
                            model.select(appointment.id); navigate("chart")
                        }
                    }.font(.subheadline).padding(.top, 6)
                }
            }
            if screenID == "patients" {
                let unique = Dictionary(workspace.appointments.map { ($0.patient_id, $0) }, uniquingKeysWith: { first, _ in first })
                DoctorPatientHistoryView(
                    patients: unique.values.map { DoctorDashboardPatient(id: $0.patient_id, name: $0.patient_name, record: $0.record_number) }.sorted { $0.name < $1.name },
                    loadHistory: { patient, from, to in try await model.patientHistory(patient: patient, from: from, to: to) })
                    .id(model.day)
            }
        }
    }

    private func patientPicker(_ workspace: DoctorWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Paciente / turno", selection: Binding(get: { model.selectedAppointmentID }, set: { model.select($0) })) {
                Text("Seleccionar paciente").tag(nil as UUID?)
                ForEach(workspace.appointments) { appointment in
                    Text("\(appointment.patient_name) · \(appointment.ticket_number ?? appointment.record_number)")
                        .tag(Optional(appointment.id))
                }
            }.pickerStyle(.menu)
            if let patient = model.selectedAppointment {
                detail("Paciente", patient.patient_name)
                detail("Turno", patient.ticket_number ?? "Sin turno asignado")
                detail("Teléfono", patient.phone ?? "No registrado")
            } else { empty("Selecciona un paciente de tu agenda.") }
        }
    }

    private func consultation(_ workspace: DoctorWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            DoctorConsultationAgendaView(day: $model.day,
                appointments: workspace.appointments,
                search: search, period: period, demonstration: false,
                select: { model.select($0) })
                .onChange(of: model.day) { _, _ in model.select(nil); Task { await model.refresh() } }
            if !workspace.appointments.isEmpty { patientPicker(workspace) }
            if let appointment = model.selectedAppointment {
                if appointment.encounter_id == nil {
                    Button("Iniciar consulta", systemImage: "cross.case.fill") { Task { await model.startConsultation() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!["checked_in", "in_progress"].contains(appointment.status))
                } else if let encounter = model.activeConsultation {
                    detail("Inicio de consulta", DoctorDate.display(encounter.started_at))
                    if model.canEditConsultation {
                        field("Motivo y síntomas", text: $model.draft.subjective)
                        field("Exploración física", text: $model.draft.objective)
                        field("Evaluación clínica", text: $model.draft.assessment)
                        Picker("Buscar diagnóstico por", selection: $model.diagnosisByCode) {
                            Text("Descripción").tag(false)
                            Text("Código CIE-10").tag(true)
                        }.pickerStyle(.segmented)
                        TextField("Buscar diagnóstico", text: $model.diagnosisQuery).textFieldStyle(.roundedBorder)
                        Button("Buscar diagnóstico", systemImage: "magnifyingglass") { Task { await model.searchDiagnoses() } }
                            .disabled(model.diagnosisQuery.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || model.searchingDiagnoses)
                        Picker("Diagnóstico principal", selection: $model.selectedDiagnosis) {
                            Text("Sin diagnóstico codificado").tag(nil as UUID?)
                            ForEach(model.diagnoses) { diagnosis in Text(diagnosis.code + " · " + diagnosis.description).tag(Optional(diagnosis.id)) }
                        }
                        field("Plan e indicaciones", text: $model.draft.plan)
                        Button("Guardar consulta", systemImage: "square.and.arrow.down") { Task { await model.saveConsultation() } }
                            .buttonStyle(.borderedProminent).disabled(!model.draft.isValid)
                        Button("Emitir orden de laboratorio", systemImage: "testtube.2") { navigate("laboratory") }
                        Button("Firmar y cerrar", systemImage: "signature") { confirmClose = true }
                            .disabled(encounter.note_id == nil)
                    } else {
                        consultationRecord(encounter)
                        HospitalBadge(text: "Consulta cerrada")
                    }
                }
            }
        }
    }

    private func laboratory(_ workspace: DoctorWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Emitir orden").font(.headline)
            patientPicker(workspace)
            detail("Clínica", workspace.facility_name)
            detail("Médico emisor", workspace.doctor_name)
            if model.canEditConsultation {
                Picker("Tipo de laboratorio", selection: $model.selectedTestID) {
                    Text("Seleccionar estudio").tag(nil as UUID?)
                    ForEach(workspace.tests) { test in Text("\(test.code) · \(test.name)").tag(Optional(test.id)) }
                }.pickerStyle(.menu)
                if workspace.tests.isEmpty { empty("No hay estudios activos en el catálogo.") }
                field("Indicaciones u observaciones", text: $model.instructions)
                Button("Emitir orden", systemImage: "paperplane") { Task { await model.issueOrder() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selectedTestID == nil || model.instructions.count > 10000)
            } else if model.selectedAppointment != nil {
                empty("La emisión requiere una consulta activa de este paciente.")
                Button("Ir a consulta", systemImage: "cross.case") { navigate("consultation") }
            }
            Text("Órdenes del día").font(.headline)
            let orders = workspace.orders.filter { matches($0.patient_name + " " + $0.test_name) }
            if orders.isEmpty { empty("No hay órdenes que coincidan con la búsqueda.") }
            ForEach(orders) { order in
                HospitalCard {
                    Text(order.test_name).font(.subheadline.weight(.semibold))
                    detail("Paciente", order.patient_name)
                    detail("Turno", order.ticket_number ?? "Sin turno asignado")
                    detail("Teléfono", order.phone ?? "No registrado")
                    detail("Emisión", DoctorDate.display(order.issued_at))
                    detail("Clínica", order.facility_name)
                    detail("Médico", order.doctor_name)
                    detail("Indicaciones", order.instructions ?? "Sin indicaciones adicionales")
                    HospitalBadge(text: status(order.status), warning: order.status != "completed")
                }
            }
        }
    }

    private func patientChart(_ workspace: DoctorWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            patientPicker(workspace)
            if let chart = model.chart {
                Text("Identificación y contacto").font(.headline)
                HospitalCard {
                    detail("Nombre", chart.patient.full_name)
                    detail("Expediente", chart.patient.record_number)
                    detail("Identificación", chart.patient.identification ?? "No registrada")
                    detail("Fecha de nacimiento", chart.patient.birth_date ?? "No registrada")
                    detail("Sexo", chart.patient.sex ?? "No registrado")
                    detail("Teléfono", chart.patient.phone ?? "No registrado")
                    detail("Correo", chart.patient.email ?? "No registrado")
                    detail("Dirección", chart.patient.address ?? "No registrada")
                }
                Text("Datos clínicos").font(.headline)
                HospitalCard {
                    detail("Grupo sanguíneo", chart.blood_type ?? "No registrado")
                    detail("Alergias registradas", chart.allergies.isEmpty ? "Sin registros" : chart.allergies.joined(separator: "\n"))
                    detail("Condiciones registradas", chart.conditions.isEmpty ? "Sin registros" : chart.conditions.joined(separator: "\n"))
                    detail("Antecedentes", (chart.medical_history ?? []).isEmpty ? "Sin registros" : (chart.medical_history ?? []).joined(separator: "\n"))
                    detail("Medicamentos", (chart.medications ?? []).isEmpty ? "Sin registros" : (chart.medications ?? []).joined(separator: "\n"))
                    ForEach(Array((chart.vitals ?? []).enumerated()), id: \.offset) { _, vital in
                        detail(vital.label, DoctorDate.parse(vital.value) == nil ? vital.value : DoctorDate.display(vital.value))
                    }
                }
            }
            if model.selectedAppointment != nil {
                Text("Historial de mis consultas").font(.headline)
                TextField("Buscar en el historial", text: $model.historyQuery).textFieldStyle(.roundedBorder)
                Toggle("Filtrar por fecha y hora", isOn: $model.filterDates)
                if model.filterDates {
                    DatePicker("Desde", selection: $model.historyFrom, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Hasta", selection: $model.historyTo, displayedComponents: [.date, .hourAndMinute])
                }
                Button("Buscar consultas", systemImage: "magnifyingglass") { Task { await model.loadChart(filtered: true) } }
                if let chart = model.chart {
                    if chart.history.isEmpty { empty("No hay consultas que coincidan con los filtros.") }
                    ForEach(chart.history) { record in HospitalCard { consultationRecord(record) } }
                }
            }
        }
    }

    private func consultationRecord(_ record: DoctorConsultation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(DoctorDate.display(record.started_at)).font(.subheadline.weight(.semibold))
            HospitalBadge(text: status(record.status))
            detail("Motivo y síntomas", record.subjective ?? "Sin nota")
            detail("Exploración física", record.objective ?? "Sin nota")
            detail("Evaluación clínica", record.assessment ?? "Sin nota")
            detail("Plan", record.plan ?? "Sin nota")
        }
    }

    private func notifications(_ values: [DoctorNotification]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let notifications = values.filter { matches($0.title + " " + $0.body) }
            if notifications.isEmpty { empty("No hay notificaciones recientes.") }
            ForEach(notifications) { notification in
                HospitalCard {
                    Label(notification.title, systemImage: notification.read_at == nil ? "bell.badge" : "bell")
                        .font(.subheadline.weight(.semibold))
                    Text(notification.body).font(.footnote)
                    Text(DoctorDate.display(notification.created_at)).font(.caption).foregroundStyle(HospitalTheme.secondary)
                    if notification.read_at == nil {
                        Button("Marcar como leída", systemImage: "checkmark") { Task { await model.markRead(notification) } }
                            .font(.caption)
                    }
                }
            }
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.medium))
            TextField(title, text: text, axis: .vertical).lineLimit(3...8)
                .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel(title)
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold))
            Text(value).font(.footnote).foregroundStyle(HospitalTheme.secondary).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func empty(_ text: String) -> some View {
        HospitalCard { Text(text).font(.footnote).foregroundStyle(HospitalTheme.secondary) }
    }

    private func status(_ value: String) -> String {
        ["open": "Abierta", "closed": "Cerrada", "draft": "Borrador", "ordered": "Emitida",
         "in_progress": "En curso", "checked_in": "Registrado en recepción", "confirmed": "Confirmado",
         "scheduled": "Programado", "completed": "Finalizado", "cancelled": "Cancelado",
         "pending": "Pendiente", "no_show": "No se presentó"][value] ?? "Estado no disponible"
    }

}
