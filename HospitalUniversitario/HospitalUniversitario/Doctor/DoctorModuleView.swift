import SwiftUI

@MainActor
struct DoctorModuleView: View {
    @ObservedObject var model: DoctorViewModel
    let screenID: String
    let search: String
    let navigate: (String) -> Void
    let period: (String) -> String
    @State private var confirmClose = false
    @State private var confirmAdmission = false
    @State private var confirmLabs = false

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
                if !["home", "notifications", "consultation", "agenda", "patients", "laboratory", "admissions"].contains(screenID) { dayPicker }
                switch screenID {
                case "home": dashboard(workspace)
                case "patients": directory(workspace, laboratory: false)
                case "consultation", "agenda": consultation(workspace)
                case "prescriptions": prescriptions(workspace)
                case "chart": patientChart(workspace)
                case "laboratory": directory(workspace, laboratory: true)
                case "admissions": admissionsView
                case "notifications": notifications(workspace.notifications)
                default: EmptyView()
                }
            } else if !model.loading && model.error == nil {
                empty("No hay información disponible para esta sede.")
            }
        }
        .disabled(model.saving || model.loading || model.loadingChart)
        .task(id: "\(screenID)/\(model.selectedAppointmentID?.uuidString ?? "")/\(model.selectedPatient?.id.uuidString ?? "")") {
            await model.loadChart()
            if screenID == "laboratory" { await model.loadPatientLabs() }
        }
        .confirmationDialog("¿Firmar y cerrar la consulta?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Firmar y cerrar", role: .destructive) { Task { await model.closeConsultation() } }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("La nota quedará firmada y la atención finalizará. Esta acción no puede deshacerse desde la app.")
        }
        .confirmationDialog("¿Enviar solicitud de ingreso a recepción?", isPresented:$confirmAdmission, titleVisibility:.visible) {
            Button("Confirmar envío") { Task { await model.requestAdmission() } }
            Button("Cancelar",role:.cancel) { }
        } message: {
            Text("Recepción verificará disponibilidad y confirmará la habitación y cama. Esta solicitud no ocupa una cama.")
        }
        .confirmationDialog("¿Enviar los exámenes seleccionados al laboratorio?",isPresented:$confirmLabs,titleVisibility:.visible) {
            Button("Confirmar exámenes") { Task { await model.issueSelectedLabs() } }
            Button("Cancelar",role:.cancel) { }
        } message: { Text("Se crearán órdenes para los exámenes seleccionados dentro de la consulta autorizada.") }
    }

    private var admissionsView: some View {
        VStack(alignment:.leading,spacing:18) {
            VStack(alignment:.leading,spacing:10) {
                Label("INGRESOS HOSPITALARIOS",systemImage:"bed.double.fill").font(.caption.bold())
                Text("Solicita el cuidado que tu paciente necesita").font(.title2.bold())
                Text("Tú indicas el motivo clínico. Recepción verifica disponibilidad y confirma la cama.").font(.subheadline)
            }.foregroundStyle(.white).padding(20).frame(maxWidth:.infinity,alignment:.leading)
                .background(LinearGradient.vinoDestacado,in:RoundedRectangle(cornerRadius:22))
            if model.admissionsLoading { ProgressView("Consultando solicitudes…") }
            if let error=model.admissionsError {
                HospitalNotice(text:error)
                Button("Actualizar solicitudes") { Task { await model.loadAdmissions() } }
            }
            if !model.admissionForm {
                Button("Nueva solicitud",systemImage:"plus.circle.fill") { model.admissionForm=true }
                    .buttonStyle(HospitalPrimaryButtonStyle())
            } else {
                admissionFormView
            }
            HStack {
                Text("Mis solicitudes").font(.headline)
                Spacer()
                Button("Actualizar",systemImage:"arrow.clockwise") { Task { await model.loadAdmissions() } }.labelStyle(.iconOnly)
            }
            if model.admissions.isEmpty && !model.admissionsLoading && model.admissionsError == nil {
                HospitalCard { Text("Todavía no has enviado solicitudes de ingreso.").foregroundStyle(HospitalTheme.secondary) }
            }
            ForEach(model.admissions) { admission in admissionCard(admission) }
            if model.admissionsPage?.has_more == true {
                Button("Cargar más solicitudes") { Task { await model.loadAdmissions(more:true) } }.disabled(model.admissionsLoading)
            }
        }.task { await model.loadAdmissions() }
            .task(id:model.admissionForm) { if model.admissionForm && model.directoryPage == nil { await model.loadPatients() } }
    }
    private var admissionFormView: some View {
        HospitalCard {
            Text("Nueva solicitud de ingreso").font(.title3.bold())
            if let pending=model.pendingAdmission {
                HospitalNotice(text:"Envío sin confirmar. Reintenta la misma solicitud para evitar duplicados.")
                detail("Paciente del envío",pending.patientName)
                detail("Expediente del envío",pending.recordNumber ?? "No disponible")
                detail("Categoría del envío",DoctorAdmissionLabels.category(pending.category))
                detail("Motivo del envío",pending.reason)
            }
            Group {
                if let name=model.pendingAdmission?.patientName ?? model.selectedPatient?.full_name ?? model.selectedAppointment?.patient_name {
                    detail("Paciente",name)
                    detail("Expediente",model.pendingAdmission?.recordNumber ?? model.selectedPatient?.record_number ?? model.selectedAppointment?.record_number ?? "No disponible")
                    Button("Cambiar paciente") { model.dismissPatient() }
                } else {
                    Text("1. Selecciona un paciente autorizado").font(.headline)
                    TextField("Nombre, DUI o correo",text:$model.patientQuery).autocorrectionDisabled().textInputAutocapitalization(.never)
                    Button("Buscar pacientes") { Task { await model.loadPatients() } }
                    if model.directoryLoading { ProgressView() }
                    if let error=model.directoryError { HospitalNotice(text:error) }
                    ForEach(model.patientDirectory) { patient in
                        Button { model.openPatient(patient) } label: {
                            VStack(alignment:.leading) { Text(patient.full_name).bold(); Text(patient.record_number ?? "Expediente no disponible").font(.caption) }.frame(maxWidth:.infinity,alignment:.leading)
                        }.buttonStyle(.bordered)
                    }
                    if model.patientDirectory.isEmpty && !model.directoryLoading { Text("No hay pacientes que coincidan. Busca entre tus pacientes asignados.").font(.footnote) }
                    if model.directoryPage?.has_more == true { Button("Cargar más pacientes") { Task { await model.loadPatients(more:true) } } }
                }
                detail("Médico solicitante",model.admissionsPage?.doctor_name ?? "Cargando identidad…")
                Text("2. Indica el cuidado requerido").font(.headline)
                Picker("Categoría de habitación",selection:$model.admissionCategory) {
                    Text("Seleccionar categoría").tag("")
                    ForEach(model.admissionsPage?.categories ?? [],id:\.self) { kind in Text(DoctorAdmissionLabels.category(kind)).tag(kind) }
                }
                if model.admissionsPage?.categories.isEmpty != false { Text("No hay categorías disponibles en el catálogo. Actualiza o contacta a recepción.").font(.footnote) }
                Picker("Prioridad",selection:$model.admissionPriority) {
                    ForEach(model.admissionsPage?.priorities ?? [],id:\.self) { priority in Text(priority == "urgente" ? "Urgente" : priority == "normal" ? "Normal" : priority).tag(priority) }
                }
                field("Motivo clínico del ingreso",text:$model.admissionReason)
                field("Observaciones e indicaciones (opcional)",text:$model.admissionObservations)
                Text("La categoría solicitada no garantiza disponibilidad ni reserva habitación.").font(.footnote).foregroundStyle(HospitalTheme.secondary)
            }.disabled(model.pendingAdmission != nil)
            Button(model.pendingAdmission == nil ? "Revisar y enviar solicitud" : "Reintentar el mismo envío") { confirmAdmission=true }
                .buttonStyle(HospitalPrimaryButtonStyle()).disabled(!model.canRequestAdmission || model.admissionsPage == nil)
            Button("Volver al listado") { model.admissionForm=false }
        }
    }
    private func admissionCard(_ admission:DoctorAdmission) -> some View {
        HospitalCard {
            Text(admission.patient_name).font(.headline)
            Label(DoctorAdmissionLabels.status(admission.decision ?? admission.status),systemImage:"bed.double").foregroundStyle(HospitalTheme.wine).font(.subheadline.bold())
            Text("\(DoctorAdmissionLabels.category(admission.category)) · \(admission.priority == "urgente" ? "Urgente" : admission.priority) · \(DoctorDate.display(admission.ordered_at))").font(.caption).foregroundStyle(HospitalTheme.secondary)
            DisclosureGroup("Ver detalle de la solicitud") {
                VStack(alignment:.leading,spacing:12) {
                    detail("Expediente",admission.record_number ?? "No disponible")
                    detail("Médico solicitante",admission.doctor_name)
                    detail("Motivo clínico",admission.reason)
                    if let observations=admission.observations { detail("Observaciones",observations) }
                    if let reason=admission.decision_reason { detail("Respuesta de recepción",reason) }
                    if let assignment=admission.assignment {
                        detail("Habitación y cama","\(assignment.room) · \(assignment.bed) · \(assignment.floor)")
                        detail("Asignación confirmada",DoctorDate.display(assignment.assigned_at))
                    } else { Text("Recepción aún no ha confirmado habitación ni cama.").font(.footnote) }
                    ForEach(Array(admission.history.enumerated()),id:\.offset) { _,event in
                        Text("\(DoctorAdmissionLabels.status(event.decision ?? event.status)) · \(DoctorDate.display(event.at))").font(.caption)
                    }
                }.padding(.top,12)
            }
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
            pendingCount: workspace.appointments.filter { ["scheduled","confirmed","in_progress"].contains($0.status) }.count,
            completedCount: workspace.appointments.filter { $0.status == "completed" }.count,
            nextAppointment: workspace.appointments.first { $0.status == "in_progress" || (["scheduled","confirmed"].contains($0.status) && ($0.startDate ?? .distantPast) >= Date()) },
            period: period,
            navigate: navigate)
    }

    private func matches(_ text: String) -> Bool { search.isEmpty || text.localizedCaseInsensitiveContains(search) }

    private func directory(_ workspace: DoctorWorkspace, laboratory: Bool) -> some View {
        VStack(alignment:.leading,spacing:18) {
            VStack(alignment:.leading,spacing:10) {
                Label(laboratory ? "LABORATORIOS" : "MIS PACIENTES",systemImage:laboratory ? "testtube.2" : "person.2.fill").font(.caption.bold()).tracking(1.2)
                Text(laboratory ? "Un paciente, toda su información" : "Tus pacientes, siempre a mano").font(.title2.bold())
                Text("Busca por nombre, DUI o correo. Solo aparecen pacientes que tienes autorización para atender.").font(.subheadline)
                if let page=model.directoryPage { Text("\(page.total) \(page.total == 1 ? "paciente encontrado" : "pacientes encontrados")").font(.caption.bold()) }
            }.foregroundStyle(.white).padding(20).frame(maxWidth:.infinity,alignment:.leading)
                .background(LinearGradient.vinoDestacado,in:RoundedRectangle(cornerRadius:22))
            HStack(spacing:10) {
                Image(systemName:"magnifyingglass").foregroundStyle(HospitalTheme.wine)
                TextField("Nombre, DUI o correo",text:$model.patientQuery).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.search).onSubmit { Task { model.dismissPatient(); await model.loadPatients() } }
                Button("Buscar") { Task { model.dismissPatient(); await model.loadPatients() } }
                    .font(.subheadline.bold()).disabled(model.directoryLoading)
            }.padding(14).background(.white,in:RoundedRectangle(cornerRadius:16))
            if model.directoryLoading { ProgressView("Buscando tus pacientes…") }
            if let error=model.directoryError {
                HospitalNotice(text:error)
                Button("Reintentar búsqueda") { Task { await model.loadPatients() } }
            }
            if laboratory && model.selectedPatient == nil { ownLabOrdersView }
            if let patient=model.selectedPatient {
                Button { model.dismissPatient() } label: { Label("Volver al listado de pacientes",systemImage:"chevron.left") }.font(.subheadline.weight(.semibold))
                HospitalCard {
                    HStack(alignment:.top,spacing:14) {
                        Text(patient.initials).font(.title3.bold()).foregroundStyle(HospitalTheme.wine)
                            .frame(width:54,height:54).background(HospitalTheme.rose,in:Circle())
                        VStack(alignment:.leading,spacing:6) {
                            Text(patient.full_name).font(.title3.bold())
                            Text(patient.record_number.map { "Expediente \($0)" } ?? "Expediente no disponible").font(.subheadline).foregroundStyle(HospitalTheme.wine)
                            Text(patient.age.map { "\($0) años" } ?? "Edad no registrada").font(.caption).foregroundStyle(HospitalTheme.secondary)
                        }
                    }
                    Divider()
                    Label(patient.dui ?? "DUI no registrado",systemImage:"person.text.rectangle").font(.subheadline)
                    Label(patient.email ?? "Correo no registrado",systemImage:"envelope").font(.subheadline).textSelection(.enabled)
                    Label(patient.phone ?? "Teléfono no registrado",systemImage:"phone").font(.subheadline)
                }
                if laboratory {
                    DisclosureGroup("Ver expediente completo del paciente") { patientChart(workspace,showPicker:false).padding(.top,12) }
                        .font(.subheadline.weight(.semibold)).padding(16).background(.white,in:RoundedRectangle(cornerRadius:16))
                    self.laboratory(workspace)
                } else {
                    patientChart(workspace,showPicker:false)
                    Button { navigate("laboratory") } label: { Label("Ver laboratorios de este paciente",systemImage:"testtube.2") }.buttonStyle(HospitalPrimaryButtonStyle())
                    Button("Abrir agenda médica") { navigate("agenda") }
                    Button("Solicitar ingreso hospitalario",systemImage:"bed.double") { model.admissionForm=true; navigate("admissions") }
                }
            } else {
                if model.patientDirectory.isEmpty && !model.directoryLoading && model.directoryError == nil {
                    HospitalCard {
                        Label("No se encontraron pacientes",systemImage:"person.crop.circle.badge.questionmark").font(.headline)
                        Text(model.patientQuery.isEmpty ? "Aquí aparecerán tus pacientes asignados, sin depender de las citas de hoy." : "Prueba otro nombre, DUI o correo dentro de tus pacientes autorizados.").font(.subheadline).foregroundStyle(HospitalTheme.secondary)
                    }
                }
                LazyVGrid(columns:[GridItem(.adaptive(minimum:240),alignment:.leading)],spacing:12) {
                    ForEach(model.patientDirectory) { patient in
                        Button { model.openPatient(patient) } label: {
                            HStack(spacing:12) {
                                Text(patient.initials).font(.headline).foregroundStyle(HospitalTheme.wine).frame(width:46,height:46).background(HospitalTheme.rose,in:Circle())
                                VStack(alignment:.leading,spacing:6) {
                                    Text(patient.full_name).font(.headline).foregroundStyle(HospitalTheme.ink).multilineTextAlignment(.leading)
                                    Text(patient.record_number ?? "Expediente no disponible").font(.caption.bold()).foregroundStyle(HospitalTheme.wine)
                                    Text(patient.email ?? "Correo no registrado").font(.caption).foregroundStyle(HospitalTheme.secondary).multilineTextAlignment(.leading)
                                    Text(laboratory ? "Abrir laboratorios y expediente" : "Ver expediente").font(.caption.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
                                }.frame(maxWidth:.infinity,alignment:.leading)
                                Image(systemName:"chevron.right").font(.caption.bold()).foregroundStyle(HospitalTheme.wine)
                            }.padding(16).frame(maxWidth:.infinity,minHeight:125,alignment:.leading)
                                .background(.white,in:RoundedRectangle(cornerRadius:18))
                                .overlay(RoundedRectangle(cornerRadius:18).stroke(HospitalTheme.rose,lineWidth:1))
                        }.buttonStyle(.plain).accessibilityLabel("Abrir expediente de \(patient.full_name)")
                    }
                }
                if model.directoryPage?.has_more == true {
                    Button("Cargar más pacientes") { Task { await model.loadPatients(more:true) } }.disabled(model.directoryLoading)
                }
            }
        }.task(id: screenID) {
            if model.directoryPage == nil { await model.loadPatients() }
            model.adoptAppointmentPatient()
            if laboratory { await model.loadLabCatalog(); await model.loadOwnLabOrders() }
        }
    }

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
                detail("Edad", DoctorConsultationFields.age(patient.age))
                detail("Expediente",patient.record_number)
                detail("Consultorio",patient.room_code ?? "No publicado")
                detail("Duración",patient.duration_minutes.map { "\($0) minutos" } ?? "No publicada")
                detail("Especialidad solicitada",patient.specialty ?? "Cita directa de recepción; sin solicitud vinculada")
                detail("Motivo original",patient.reason ?? "Sin solicitud de atención vinculada")
                detail("Síntomas declarados",DoctorConsultationFields.symptoms(patient.symptoms))
                if let other=patient.other_symptoms { detail("Otros síntomas",other) }
                detail("Turno", patient.ticket_number ?? "Sin turno asignado")
                detail("Teléfono", patient.phone ?? "No registrado")
            } else { empty("Selecciona un paciente de tu agenda.") }
        }
    }

    private func consultation(_ workspace: DoctorWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Estado",selection:$model.statusFilter) {
                Text("Todos").tag("all"); Text("Programadas").tag("scheduled"); Text("Confirmadas").tag("confirmed")
                Text("En atención").tag("in_progress"); Text("Atendidas").tag("completed"); Text("Canceladas").tag("cancelled"); Text("No asistió").tag("no_show")
            }.pickerStyle(.menu)
            DoctorConsultationAgendaView(day: $model.day,
                appointments: workspace.appointments.filter { model.statusFilter == "all" || $0.status == model.statusFilter },
                search: search, period: period, demonstration: false,
                select: { model.select($0); if screenID == "agenda" { navigate("consultation") } })
                .onChange(of: model.day) { _, _ in model.select(nil); Task { await model.refresh() } }
            if !workspace.appointments.isEmpty { patientPicker(workspace) }
            if let appointment = model.selectedAppointment {
                if appointment.encounter_id == nil {
                    Button("Iniciar consulta", systemImage: "cross.case.fill") { Task { await model.startConsultation() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!["scheduled", "confirmed", "in_progress"].contains(appointment.status))
                } else if let encounter = model.activeConsultation {
                    detail("Inicio de consulta", DoctorDate.display(encounter.started_at))
                    if model.canEditConsultation {
                        field("Motivo y síntomas", text: $model.draft.subjective)
                        field("Exploración física", text: $model.draft.objective)
                        field("Diagnóstico y evaluación clínica", text: $model.draft.assessment)
                        TextField("Código diagnóstico (opcional, sin catálogo publicado)", text:$model.draft.diagnosis_code).textFieldStyle(.roundedBorder)
                        vitalsForm
                        field("Plan e indicaciones", text: $model.draft.plan)
                        Button("Guardar consulta", systemImage: "square.and.arrow.down") { Task { await model.saveConsultation() } }
                            .buttonStyle(.borderedProminent).disabled(!model.draft.canSave)
                        Button("Revisar expediente", systemImage: "doc.text") { navigate("chart") }
                        Button("Emitir orden de laboratorio", systemImage: "testtube.2") { navigate("laboratory") }
                        Button("Emitir receta", systemImage: "pills") { navigate("prescriptions") }
                        Button("Solicitar ingreso hospitalario",systemImage:"bed.double") { model.admissionForm=true; navigate("admissions") }
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
            Text("Solicitar exámenes").font(.title3.bold())
            if model.canEditConsultation || model.pendingLabs != nil {
                labSelectionView
            } else {
                empty("Este paciente no tiene una consulta tuya abierta. Iníciala desde su cita en Agenda para emitir una orden.")
                Button("Ir a consulta", systemImage: "cross.case") { navigate("consultation") }
            }
            Text("Exámenes y resultados del paciente").font(.headline)
            Text("Resultados autorizados de este expediente, sin limitarse a la agenda del día.").font(.footnote).foregroundStyle(HospitalTheme.secondary)
            if model.patientLabsLoading { ProgressView("Cargando exámenes…") }
            if let error=model.patientLabsError {
                HospitalNotice(text:error)
                Button("Reintentar laboratorios") { Task { await model.loadPatientLabs() } }
            }
            let orders = model.patientLabs
            if orders.isEmpty && !model.patientLabsLoading && model.patientLabsError == nil { empty("Este paciente todavía no tiene exámenes registrados.") }
            ForEach(orders) { order in
                labOrderCard(order)
            }
            if model.patientLabPage?.has_more == true { Button("Cargar más exámenes") { Task { await model.loadPatientLabs(more:true) } }.disabled(model.patientLabsLoading) }
        }
    }

    private var labSelectionView: some View {
        HospitalCard {
            if model.labCatalogLoading { ProgressView("Cargando catálogo…") }
            if let error=model.labCatalogError {
                HospitalNotice(text:error)
                Button("Reintentar catálogo") { Task { await model.loadLabCatalog() } }
            }
            Group {
                TextField("Buscar exámenes",text:$model.labQuery).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                Picker("Categoría de examen",selection:$model.labCategory) {
                    Text("Todas las categorías").tag("all")
                    ForEach(Array(Set(model.labCatalog.map { $0.category ?? "Sin categoría" })).sorted(),id:\.self) { Text($0).tag($0) }
                }
                if model.filteredLabTests.isEmpty && !model.labCatalogLoading {
                    Text(model.labCatalog.isEmpty ? "No hay exámenes activos. Actualiza el catálogo o contacta al laboratorio." : "No hay exámenes que coincidan con la búsqueda.").font(.footnote)
                }
                LazyVGrid(columns:[GridItem(.adaptive(minimum:220))],spacing:10) {
                    ForEach(model.filteredLabTests) { test in
                        Button {
                            if model.selectedLabIDs.contains(test.id) { model.selectedLabIDs.remove(test.id) }
                            else if model.selectedLabIDs.count<30 { model.selectedLabIDs.insert(test.id) }
                        } label: {
                            HStack(alignment:.top) {
                                Image(systemName:model.selectedLabIDs.contains(test.id) ? "checkmark.circle.fill" : "circle")
                                VStack(alignment:.leading,spacing:5) { Text(test.name).font(.subheadline.bold()); Text(test.category ?? "Sin categoría").font(.caption) }
                                Spacer(minLength:0)
                            }.padding(14).frame(maxWidth:.infinity,alignment:.leading)
                                .background(model.selectedLabIDs.contains(test.id) ? HospitalTheme.rose : HospitalTheme.background,in:RoundedRectangle(cornerRadius:14))
                        }.buttonStyle(.plain).foregroundStyle(HospitalTheme.wine).accessibilityLabel("Seleccionar \(test.name)")
                    }
                }
                Text("Resumen · \(model.selectedLabIDs.count) exámenes seleccionados").font(.headline)
                ForEach(model.labCatalog.filter { model.selectedLabIDs.contains($0.id) }) { test in Text("• \(test.name)").font(.subheadline) }
                field("Motivo e indicaciones clínicas",text:$model.instructions)
            }.disabled(model.pendingLabs != nil)
            if let pending=model.pendingLabs {
                HospitalNotice(text:"Envío sin confirmar. Se reintentará exactamente la misma selección, sin duplicar órdenes.")
                detail("Paciente del envío",pending.patientName)
                detail("Expediente del envío",pending.recordNumber ?? "No disponible")
                Text(pending.reason).font(.footnote)
            }
            Button(model.pendingLabs == nil ? "Revisar y enviar exámenes" : "Reintentar el mismo envío",systemImage:"paperplane.fill") { confirmLabs=true }
                .buttonStyle(HospitalPrimaryButtonStyle()).disabled(!model.canIssueLabs)
        }
    }
    private var ownLabOrdersView: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Text("Mis órdenes de laboratorio").font(.headline); Spacer(); Button("Actualizar órdenes") { Task { await model.loadOwnLabOrders() } } }
            if let pending=model.pendingLabs {
                HospitalCard {
                    Text("Envío sin confirmar · \(pending.patientName)").font(.headline)
                    Text("\(pending.tests.count) exámenes · \(pending.reason)").font(.footnote)
                    Button("Reintentar el mismo envío") { confirmLabs=true }.buttonStyle(HospitalPrimaryButtonStyle())
                }
            }
            if model.ownLabsLoading { ProgressView() }
            if let error=model.ownLabsError { HospitalNotice(text:error) }
            if model.ownLabOrders.isEmpty && !model.ownLabsLoading && model.ownLabsError == nil { empty("Todavía no has solicitado exámenes de laboratorio.") }
            ForEach(model.ownLabOrders) { labOrderCard($0) }
            if model.ownLabPage?.has_more == true { Button("Cargar más órdenes") { Task { await model.loadOwnLabOrders(more:true) } } }
            Text("Busca un paciente abajo para revisar su expediente o solicitar exámenes desde una consulta abierta.").font(.footnote).foregroundStyle(HospitalTheme.secondary)
        }
    }
    private func labOrderCard(_ order:DoctorPatientLab) -> some View {
        HospitalCard {
            Text(order.test_name).font(.headline)
            if let patient=order.patient_name { Text(patient).font(.subheadline) }
            Text(DoctorDate.display(order.ordered_at)).font(.caption).foregroundStyle(HospitalTheme.secondary)
            if order.status == "pendiente" { ClinicalLabStateBadge(state:.pending) }
            else if order.status == "en_proceso" { ClinicalLabStateBadge(state:.processing) }
            else if order.status == "completado" { ClinicalLabStateBadge(state:.completed) }
            else { Text(status(order.status)).font(.caption) }
            DisclosureGroup("Ver detalle del examen") {
                VStack(alignment:.leading,spacing:12) {
                    if let record=order.record_number { detail("Expediente",record) }
                    detail("Motivo e indicaciones",order.reason)
                    if let summary=order.result_summary {
                        detail("Resultado validado y publicado",summary)
                        ForEach(Array((order.parameters ?? []).enumerated()),id:\.offset) { _,parameter in
                            detail(parameter.label,[parameter.value,parameter.unit].compactMap { $0 }.joined(separator:" "))
                            if let reference=parameter.reference, !reference.isEmpty { detail("Referencia del laboratorio",reference) }
                            if let observation=parameter.observation, !observation.isEmpty { detail("Observación",observation) }
                        }
                        if let date=order.published_at { detail("Publicado",DoctorDate.display(date)) }
                    } else { Text("El laboratorio está procesando la orden o aún no ha publicado un resultado validado.").font(.footnote) }
                }.padding(.top,10)
            }
        }
    }

    private func patientChart(_ workspace: DoctorWorkspace,showPicker: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if showPicker { patientPicker(workspace) }
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
            if model.selectedAppointment != nil || model.selectedPatient != nil {
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
    private var vitalsForm: some View {
        HospitalCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Signos vitales (solo valores medidos)").font(.headline)
                ForEach(["weight_kg","height_cm","systolic","diastolic","temperature_c","heart_rate"],id: \.self) { key in
                    let label=["weight_kg":"Peso (kg)","height_cm":"Altura (cm)","systolic":"Presión sistólica (mmHg)",
                        "diastolic":"Presión diastólica (mmHg)","temperature_c":"Temperatura (°C)","heart_rate":"Frecuencia cardíaca (lpm)"][key] ?? key
                    TextField(label,text:Binding(get:{model.draft.vitals[key] ?? ""},set:{ value in
                        if value.isEmpty { model.draft.vitals.removeValue(forKey:key) } else { model.draft.vitals[key]=value }
                    })).keyboardType(.decimalPad).textFieldStyle(.roundedBorder).accessibilityLabel(label)
                }
            }
        }
    }
    private func prescriptions(_ workspace: DoctorWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            patientPicker(workspace)
            if model.canEditConsultation {
                HospitalCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Emitir receta").font(.headline)
                        Picker("Medicamento y concentración",selection:$model.rxMedication) {
                            Text("Seleccionar medicamento").tag(nil as UUID?)
                            ForEach(workspace.medications ?? []) { Text($0.label).tag(Optional($0.id)) }
                        }.pickerStyle(.menu)
                        if (workspace.medications ?? []).isEmpty { Text("No hay medicamentos activos publicados en el catálogo.").font(.footnote) }
                        TextField("Dosis",text:$model.rxDose).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                        TextField("Unidad de dosis",text:$model.rxUnit).textFieldStyle(.roundedBorder)
                        TextField("Frecuencia: cada cuántas horas",text:$model.rxFrequency).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                        Picker("Vía",selection:$model.rxRoute) { Text("Oral").tag("oral"); Text("Inyectable").tag("inyectable") }
                        TextField("Duración en días",text:$model.rxDays).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                        TextField("Cantidad total",text:$model.rxQuantity).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                        TextField("Indicaciones",text:$model.rxInstructions,axis:.vertical).textFieldStyle(.roundedBorder)
                        Button("Añadir medicamento") { model.addMedication() }
                        ForEach(model.rxLines) { line in
                            VStack(alignment:.leading,spacing:6) {
                                Text(line.medication.label).font(.subheadline.bold())
                                Text("\(line.dose.description) \(line.unit) · cada \(line.frequency) h · \(line.days) días · \(line.route)").font(.footnote)
                                Button("Retirar de esta receta",role:.destructive) { model.rxLines.removeAll { $0.id == line.id } }.font(.caption)
                            }
                        }
                        Button("Emitir receta autorizada") { Task { await model.issuePrescription() } }
                            .buttonStyle(HospitalPrimaryButtonStyle()).disabled(model.rxLines.isEmpty)
                    }
                }
            } else {
                Text("Selecciona e inicia una consulta asignada para emitir recetas.").font(.footnote)
                Button("Ir a consulta") { navigate("consultation") }
            }
            Text("Recetas de mis consultas de este paciente").font(.headline)
            ForEach(model.contextChart?.prescriptions ?? []) { prescription in
                HospitalCard {
                    Text(prescription.code).font(.headline)
                    Text(DoctorDate.display(prescription.issued_at)).font(.caption)
                    Text(prescription.status == "pendiente" ? "Pendiente de entrega" : prescription.status).font(.caption)
                    ForEach(Array(prescription.lines.enumerated()),id: \.offset) { _, line in Text(line).font(.footnote) }
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
         "pending": "Pendiente", "pendiente": "Pendiente", "en_proceso": "En proceso", "completado": "Completado", "entregada": "Entregada", "anulada": "Anulada", "no_show": "No se presentó"][value] ?? "Estado no disponible"
    }

}
