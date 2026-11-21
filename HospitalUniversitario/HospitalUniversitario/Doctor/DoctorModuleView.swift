import SwiftUI

@MainActor
struct DoctorModuleView: View {
    @ObservedObject var model: DoctorViewModel
    let screenID: String
    let search: String
    let navigate: (String) -> Void
    let period: (String) -> String
    @State private var confirmFinish = false
    @State private var confirmLeave = false
    @State private var confirmAdmission = false
    @State private var confirmTransport = false
    @State private var confirmLabs = false
    @State private var confirmSheetLabs = false
    @State private var confirmPrescription = false
    @State private var clinicalSheet: ClinicalSheet?
    @State private var medicationQuery = ""
    private enum ClinicalSheet: String, Identifiable { case labs, prescription; var id: String { rawValue } }

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
            if !["home", "notifications"].contains(screenID), let notice = model.alerts.first(where: { $0.read_at == nil }) {
                HospitalCard {
                    Label(notice.title, systemImage: "bell.badge").font(.subheadline.bold()).foregroundStyle(HospitalTheme.wine)
                    Button("Ver avisos") { navigate("notifications") }
                }
            }
            if let workspace = model.workspace {
                if !["home", "notifications", "consultation", "agenda", "patients", "chart", "laboratory", "admissions", "ambulance"].contains(screenID) { dayPicker }
                switch screenID {
                case "home": dashboard(workspace)
                // Expedientes: buscador y expediente sin selector desplegable (paridad con web-preview).
                case "patients", "chart": DoctorRecordsView(model: model, workspace: workspace, navigate: navigate)
                case "consultation", "agenda": consultation(workspace)
                case "prescriptions": prescriptions(workspace)
                case "laboratory": directory(workspace, laboratory: true)
                case "admissions": admissionsView
                case "ambulance": ambulanceView
                case "notifications": notifications(model.alerts)
                default: EmptyView()
                }
            } else if !model.loading && model.error == nil {
                empty("No hay información disponible para esta sede.")
            }
        }
        .disabled(model.saving || model.loading || model.loadingChart)
        .task(id: "\(screenID)/\(model.selectedAppointmentID?.uuidString ?? "")/\(model.selectedPatient?.id.uuidString ?? "")") {
            if model.selectedAppointment?.encounter_id != nil || model.selectedPatient != nil || screenID == "chart" { await model.loadChart() }
            if screenID == "laboratory" { await model.loadPatientLabs() }
        }
        // Cancelar este cuadro solo vuelve a la consulta: no cancela la cita ni modifica datos.
        .alert("¿Estás seguro de que deseas finalizar esta consulta?", isPresented: $confirmFinish) {
            Button("Volver a la consulta", role: .cancel) { }
            Button("Confirmar y finalizar") {
                Task { if await model.closeConsultation() { navigate("agenda") } }
            }
        } message: {
            Text("Una vez finalizada, la información clínica quedará registrada en el expediente del paciente y la consulta pasará al historial médico.")
        }
        .confirmationDialog("Tienes cambios sin guardar", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Guardar y volver a la agenda") { Task { if await model.saveConsultation() { model.select(nil) } } }
            Button("Salir sin guardar", role: .destructive) { model.select(nil) }
            Button("Seguir en la consulta", role: .cancel) { }
        } message: { Text("Lo escrito desde el último guardado se perderá si sales sin guardar.") }
        .sheet(item: $clinicalSheet) { _ in clinicalSheetContent.presentationDragIndicator(.visible) }
        .confirmationDialog("¿Enviar solicitud de ingreso a recepción?", isPresented:$confirmAdmission, titleVisibility:.visible) {
            Button("Confirmar envío") { Task { await model.requestAdmission() } }
            Button("Cancelar",role:.cancel) { }
        } message: {
            Text("Recepción verificará disponibilidad y confirmará la habitación y cama. Esta solicitud no ocupa una cama.")
        }
        .confirmationDialog("¿Solicitar la ambulancia para este paciente?", isPresented:$confirmTransport, titleVisibility:.visible) {
            Button("Confirmar solicitud") { Task { await model.requestTransport() } }
            Button("Cancelar",role:.cancel) { }
        } message: {
            Text("Administración autoriza el traslado y asigna la unidad y el conductor. Si la ambulancia está en servicio, la solicitud queda en espera.")
        }
        .confirmationDialog("¿Enviar los exámenes seleccionados al laboratorio?",isPresented:$confirmLabs,titleVisibility:.visible) {
            Button("Confirmar exámenes") { Task { await model.issueSelectedLabs() } }
            Button("Cancelar",role:.cancel) { }
        } message: { Text("Se crearán órdenes para los exámenes seleccionados dentro de la consulta autorizada.") }
    }

    private var admissionsView: some View {
        VStack(alignment:.leading,spacing:16) {
            VStack(alignment:.leading,spacing:10) {
                Label("INGRESOS HOSPITALARIOS",systemImage:"bed.double.fill").font(.caption2.weight(.heavy)).tracking(1.2).opacity(0.85)
                Text("Solicita el cuidado que tu paciente necesita").font(.title2.bold())
                Text("Tú indicas el motivo clínico. Recepción verifica disponibilidad y confirma la cama.").font(.subheadline).opacity(0.9)
            }.foregroundStyle(.white).padding(20).frame(maxWidth:.infinity,alignment:.leading)
                .background(LinearGradient.vinoDestacado,in:RoundedRectangle(cornerRadius:24,style:.continuous))
                .shadow(color:HospitalTheme.wine.opacity(0.18),radius:12,y:5)
            if let error=model.admissionsError {
                HospitalNotice(text:error)
                Button("Actualizar solicitudes",systemImage:"arrow.clockwise") { Task { await model.loadAdmissions() } }.tint(HospitalTheme.wine)
            }
            if !model.admissionForm {
                Button { model.patientQuery = ""; model.admissionForm=true } label: {
                    Label("Nueva solicitud",systemImage:"plus.circle.fill").font(.headline).foregroundStyle(.white)
                        .frame(maxWidth:.infinity,minHeight:56)
                        .background(LinearGradient.vinoDestacado,in:RoundedRectangle(cornerRadius:16,style:.continuous))
                }.buttonStyle(.plain)
            } else {
                admissionFormView
            }
            HStack {
                Label("Mis solicitudes",systemImage:"list.bullet.clipboard").font(.headline).foregroundStyle(HospitalTheme.ink)
                Spacer()
                if model.admissionsLoading { ProgressView().controlSize(.small) }
                Button { Task { await model.loadAdmissions() } } label: {
                    Image(systemName:"arrow.clockwise").font(.subheadline.bold()).foregroundStyle(HospitalTheme.wine)
                        .frame(width:36,height:36).background(HospitalTheme.rose,in:Circle())
                }.buttonStyle(.plain).accessibilityLabel("Actualizar solicitudes")
            }.padding(.top,4)
            if model.admissions.isEmpty && !model.admissionsLoading && model.admissionsError == nil {
                doctorEmpty(icon:"bed.double",title:"Sin solicitudes",text:"Todavía no has enviado solicitudes de ingreso.")
            }
            ForEach(model.admissions) { admission in admissionCard(admission) }
            if model.admissionsPage?.has_more == true {
                Button("Cargar más solicitudes") { Task { await model.loadAdmissions(more:true) } }
                    .frame(maxWidth:.infinity).disabled(model.admissionsLoading).tint(HospitalTheme.wine)
            }
        }.task { await model.loadAdmissions() }
            // Búsqueda del paciente con espera breve; no se muestra ningún listado hasta escribir.
            .task(id:model.patientQuery) {
                let query=model.patientQuery.trimmingCharacters(in:.whitespacesAndNewlines)
                if model.admissionForm && model.selectedPatient == nil && model.selectedAppointment == nil && query.count >= 2 { await model.searchPatients() }
            }
    }
    private var admissionFormView: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {
                Text("Nueva solicitud de ingreso").font(.title3.bold())
                Spacer()
                Button("Cancelar") { model.admissionForm=false }.font(.subheadline.weight(.semibold)).tint(HospitalTheme.wine)
            }
            if let pending=model.pendingAdmission {
                VStack(alignment:.leading,spacing:8) {
                    Label("Envío sin confirmar",systemImage:"exclamationmark.arrow.triangle.2.circlepath").font(.subheadline.bold())
                    Text("Reintenta la misma solicitud para evitar duplicados.").font(.footnote)
                    Text("\(pending.patientName) · \(pending.recordNumber ?? "Expediente no disponible") · \(DoctorAdmissionLabels.category(pending.category))").font(.caption.weight(.semibold))
                    Text(pending.reason).font(.caption).lineLimit(3)
                }.foregroundStyle(HospitalTheme.wine).padding(14).frame(maxWidth:.infinity,alignment:.leading)
                    .background(HospitalTheme.rose,in:RoundedRectangle(cornerRadius:14,style:.continuous))
            }
            Group {
                admissionPatientStep
                Divider()
                VStack(alignment:.leading,spacing:14) {
                    ConsultationBlockHeader(letter:"2",icon:"bed.double",title:"Cuidado requerido",subtitle:"La categoría no garantiza disponibilidad ni reserva habitación.")
                    Text("Categoría de habitación").font(.subheadline.weight(.semibold))
                    if model.admissionsPage?.categories.isEmpty != false {
                        Text("No hay categorías disponibles en el catálogo. Actualiza o contacta a recepción.").font(.footnote).foregroundStyle(HospitalTheme.secondary)
                    }
                    ConsultationFlowLayout(spacing:8) {
                        ForEach(model.admissionsPage?.categories ?? [],id:\.self) { kind in
                            choiceChip(DoctorAdmissionLabels.category(kind),icon:kind == "vip" ? "star.fill" : "bed.double",selected:model.admissionCategory == kind) { model.admissionCategory=kind }
                        }
                    }
                    Text("Prioridad").font(.subheadline.weight(.semibold))
                    Picker("Prioridad",selection:$model.admissionPriority) {
                        ForEach(model.admissionsPage?.priorities ?? [],id:\.self) { priority in Text(priority == "urgente" ? "Urgente" : priority == "normal" ? "Normal" : priority).tag(priority) }
                    }.pickerStyle(.segmented)
                    Label("Médico solicitante: \(model.admissionsPage?.doctor_name ?? "Cargando identidad…")",systemImage:"stethoscope")
                        .font(.caption).foregroundStyle(HospitalTheme.secondary)
                }
                Divider()
                VStack(alignment:.leading,spacing:14) {
                    ConsultationBlockHeader(letter:"3",icon:"text.bubble",title:"Motivo clínico",subtitle:"Recepción lo usará para gestionar la cama.")
                    ConsultationNoteField(icon:"cross.case",title:"Motivo clínico del ingreso",placeholder:"Describe por qué el paciente necesita hospitalización",text:$model.admissionReason)
                    VStack(alignment:.leading,spacing:8) {
                        Label("Observaciones e indicaciones (opcional)",systemImage:"note.text").font(.subheadline.weight(.semibold))
                        TextField("Indicaciones para el equipo de hospitalización",text:$model.admissionObservations,axis:.vertical).lineLimit(3...8)
                            .padding(14).background(HospitalTheme.background,in:RoundedRectangle(cornerRadius:12,style:.continuous))
                    }
                }
            }.disabled(model.pendingAdmission != nil)
            Button { confirmAdmission=true } label: {
                Label(model.pendingAdmission == nil ? "Revisar y enviar solicitud" : "Reintentar el mismo envío",systemImage:"paperplane.fill").font(.headline).foregroundStyle(.white)
                    .frame(maxWidth:.infinity,minHeight:54)
                    .background(model.canRequestAdmission && model.admissionsPage != nil ? AnyShapeStyle(LinearGradient.vinoDestacado) : AnyShapeStyle(HospitalTheme.secondary),in:RoundedRectangle(cornerRadius:16,style:.continuous))
            }.buttonStyle(.plain).disabled(!model.canRequestAdmission || model.admissionsPage == nil)
        }.modifier(ConsultationCardStyle())
    }
    /// Paso 1: paciente elegido o buscador (nombre, apellido o DUI). Sin texto no se muestra ningún listado.
    private var admissionPatientStep: some View {
        patientStep("Paciente a hospitalizar", searchLabel:"Buscar paciente para hospitalizar", pendingName:model.pendingAdmission?.patientName, pendingRecord:model.pendingAdmission?.recordNumber)
    }
    /// Buscador de pacientes autorizados compartido por ingresos y ambulancia.
    @ViewBuilder private func patientStep(_ title:String, searchLabel:String, pendingName:String?, pendingRecord:String?) -> some View {
        VStack(alignment:.leading,spacing:12) {
            ConsultationBlockHeader(letter:"1",icon:"person.crop.circle.badge.plus",title:title,subtitle:"Busca por nombre, apellido o DUI entre tus pacientes autorizados.")
            if let name=pendingName ?? model.selectedPatient?.full_name ?? model.selectedAppointment?.patient_name {
                HStack(spacing:12) {
                    Text(DoctorAssignedPatient.initials(name)).font(.headline.bold()).foregroundStyle(HospitalTheme.wine)
                        .frame(width:48,height:48).background(HospitalTheme.rose,in:Circle())
                    VStack(alignment:.leading,spacing:3) {
                        Text(name).font(.headline)
                        Text("Expediente \(pendingRecord ?? model.selectedPatient?.record_number ?? model.selectedAppointment?.record_number ?? "no disponible")").font(.caption.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
                        if let dui=model.selectedPatient?.dui { Text("DUI \(dui)").font(.caption).foregroundStyle(HospitalTheme.secondary) }
                    }
                    Spacer(minLength:0)
                    Button("Cambiar") { model.dismissPatient(); model.patientQuery="" }.font(.subheadline.weight(.semibold)).tint(HospitalTheme.wine)
                }.padding(12).background(HospitalTheme.background,in:RoundedRectangle(cornerRadius:14,style:.continuous))
            } else {
                let query=model.patientQuery.trimmingCharacters(in:.whitespacesAndNewlines)
                HStack(spacing:10) {
                    Image(systemName:"magnifyingglass").foregroundStyle(HospitalTheme.wine)
                    TextField("Nombre, apellido o DUI",text:$model.patientQuery).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel(searchLabel)
                    if model.directoryLoading { ProgressView().controlSize(.small) }
                    else if !model.patientQuery.isEmpty {
                        Button { model.patientQuery="" } label: { Image(systemName:"xmark.circle.fill").foregroundStyle(HospitalTheme.secondary) }.accessibilityLabel("Borrar búsqueda")
                    }
                }.padding(.horizontal,14).frame(minHeight:50)
                    .background(HospitalTheme.background,in:RoundedRectangle(cornerRadius:14,style:.continuous))
                    .overlay(RoundedRectangle(cornerRadius:14,style:.continuous).stroke(HospitalTheme.rose,lineWidth:1.5))
                if query.count < 2 {
                    Label("Escribe al menos 2 letras del nombre, apellido o DUI para buscar.",systemImage:"info.circle").font(.footnote).foregroundStyle(HospitalTheme.secondary)
                } else if model.directoryLoading || model.lastDirectoryQuery != query {
                    ProgressView("Buscando pacientes…").frame(maxWidth:.infinity)
                } else if let error=model.directoryError {
                    HospitalNotice(text:error)
                } else if model.patientDirectory.isEmpty {
                    Label("Ningún paciente autorizado coincide con «\(query)».",systemImage:"person.crop.circle.badge.questionmark").font(.footnote).foregroundStyle(HospitalTheme.secondary)
                } else {
                    ForEach(model.patientDirectory) { patient in
                        Button { model.openPatient(patient) } label: {
                            HStack(spacing:12) {
                                Text(patient.initials).font(.subheadline.bold()).foregroundStyle(HospitalTheme.wine).frame(width:42,height:42).background(HospitalTheme.rose,in:Circle())
                                VStack(alignment:.leading,spacing:3) {
                                    Text(patient.full_name).font(.subheadline.weight(.semibold)).foregroundStyle(HospitalTheme.ink).multilineTextAlignment(.leading)
                                    Text([patient.record_number.map { "Exp. \($0)" }, patient.dui.map { "DUI \($0)" }, patient.age.map { "\($0) años" }].compactMap { $0 }.joined(separator:" · "))
                                        .font(.caption).foregroundStyle(HospitalTheme.secondary)
                                }
                                Spacer(minLength:0)
                                Image(systemName:"plus.circle.fill").font(.title3).foregroundStyle(HospitalTheme.wine)
                            }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
                                .background(.white,in:RoundedRectangle(cornerRadius:14,style:.continuous))
                                .overlay(RoundedRectangle(cornerRadius:14,style:.continuous).stroke(HospitalTheme.rose,lineWidth:1))
                        }.buttonStyle(.plain).accessibilityLabel("Seleccionar paciente \(patient.full_name)")
                    }
                    if model.directoryPage?.has_more == true { Button("Cargar más pacientes") { Task { await model.loadPatients(more:true) } }.tint(HospitalTheme.wine) }
                }
            }
        }
    }
    private func admissionCard(_ admission:DoctorAdmission) -> some View {
        let state=admission.decision ?? admission.status
        let done=["asignado","hospitalizado","alta_medica","cerrado"].contains(state), rejected=["rechazada","cancelado","cancelada"].contains(state)
        return VStack(alignment:.leading,spacing:10) {
            HStack(alignment:.top,spacing:12) {
                Image(systemName:"bed.double.fill").font(.headline).foregroundStyle(HospitalTheme.wine)
                    .frame(width:42,height:42).background(HospitalTheme.rose,in:RoundedRectangle(cornerRadius:12,style:.continuous))
                VStack(alignment:.leading,spacing:4) {
                    Text(admission.patient_name).font(.headline)
                    Text(DoctorDate.display(admission.ordered_at)).font(.caption).foregroundStyle(HospitalTheme.secondary)
                }
                Spacer(minLength:0)
                Text(DoctorAdmissionLabels.status(state)).font(.caption2.bold()).padding(.horizontal,8).padding(.vertical,4)
                    .foregroundStyle(done ? Color(red:0.13,green:0.5,blue:0.3) : rejected ? HospitalTheme.secondary : HospitalTheme.wine)
                    .background(done ? HospitalTheme.green : rejected ? HospitalTheme.background : HospitalTheme.rose,in:Capsule())
            }
            ConsultationFlowLayout(spacing:6) {
                choiceChip(DoctorAdmissionLabels.category(admission.category),icon:"bed.double",selected:false) {}.allowsHitTesting(false)
                choiceChip(admission.priority == "urgente" ? "Urgente" : "Normal",icon:admission.priority == "urgente" ? "exclamationmark.triangle.fill" : "clock",selected:admission.priority == "urgente") {}.allowsHitTesting(false)
            }
            if let assignment=admission.assignment {
                Label("\(assignment.room) · \(assignment.bed) · \(assignment.floor)",systemImage:"checkmark.seal.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Color(red:0.13,green:0.5,blue:0.3))
            }
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
                    } else { Text("Recepción aún no ha confirmado habitación ni cama.").font(.footnote).foregroundStyle(HospitalTheme.secondary) }
                    ForEach(Array(admission.history.enumerated()),id:\.offset) { _,event in
                        Label("\(DoctorAdmissionLabels.status(event.decision ?? event.status)) · \(DoctorDate.display(event.at))",systemImage:"circle.fill").font(.caption).foregroundStyle(HospitalTheme.secondary)
                    }
                }.padding(.top,10)
            }.font(.subheadline.weight(.semibold)).tint(HospitalTheme.wine)
        }.modifier(ConsultationCardStyle())
    }
    /// Ambulancia: estado público de la unidad, solicitud de traslado (request_medical_transport) y traslados visibles por RLS.
    private var ambulanceView: some View {
        VStack(alignment:.leading,spacing:16) {
            VStack(alignment:.leading,spacing:10) {
                Label("AMBULANCIA",systemImage:"cross.case.fill").font(.caption2.weight(.heavy)).tracking(1.2).opacity(0.85)
                Text("Solicita el traslado de tu paciente").font(.title2.bold())
                Text("Tú indicas origen, destino y motivo. Administración autoriza y despacha la unidad.").font(.subheadline).opacity(0.9)
            }.foregroundStyle(.white).padding(20).frame(maxWidth:.infinity,alignment:.leading)
                .background(LinearGradient.vinoDestacado,in:RoundedRectangle(cornerRadius:24,style:.continuous))
                .shadow(color:HospitalTheme.wine.opacity(0.18),radius:12,y:5)
            ForEach(Array((model.transportBoard?.units ?? []).enumerated()),id:\.offset) { _,unit in unitCard(unit) }
            if let error=model.transportsError {
                HospitalNotice(text:error)
                Button("Actualizar traslados",systemImage:"arrow.clockwise") { Task { await model.loadTransports() } }.tint(HospitalTheme.wine)
            }
            if !model.transportForm {
                Button { model.patientQuery = ""; model.transportForm=true; model.prefillTransportContact() } label: {
                    Label("Solicitar ambulancia",systemImage:"plus.circle.fill").font(.headline).foregroundStyle(.white)
                        .frame(maxWidth:.infinity,minHeight:56)
                        .background(LinearGradient.vinoDestacado,in:RoundedRectangle(cornerRadius:16,style:.continuous))
                }.buttonStyle(.plain)
            } else {
                transportFormView
            }
            HStack {
                Label("Traslados de mis pacientes",systemImage:"list.bullet.clipboard").font(.headline).foregroundStyle(HospitalTheme.ink)
                Spacer()
                if model.transportsLoading { ProgressView().controlSize(.small) }
                Button { Task { await model.loadTransports() } } label: {
                    Image(systemName:"arrow.clockwise").font(.subheadline.bold()).foregroundStyle(HospitalTheme.wine)
                        .frame(width:36,height:36).background(HospitalTheme.rose,in:Circle())
                }.buttonStyle(.plain).accessibilityLabel("Actualizar traslados")
            }.padding(.top,4)
            if (model.transportBoard?.items ?? []).isEmpty && !model.transportsLoading && model.transportsError == nil {
                doctorEmpty(icon:"cross.case",title:"Sin traslados",text:"Todavía no hay solicitudes de ambulancia para tus pacientes.")
            }
            ForEach(model.transportBoard?.items ?? []) { item in transportCard(item) }
        }.task { await model.loadTransports() }
            // Búsqueda del paciente con espera breve, igual que en ingresos.
            .task(id:model.patientQuery) {
                let query=model.patientQuery.trimmingCharacters(in:.whitespacesAndNewlines)
                if model.transportForm && model.selectedPatient == nil && model.selectedAppointment == nil && query.count >= 2 { await model.searchPatients() }
            }
            .onChange(of:model.selectedPatient?.id) { _,_ in if model.transportForm { model.prefillTransportContact() } }
    }
    private func unitCard(_ unit:DoctorAmbulanceUnit) -> some View {
        let available=unit.status == "disponible"
        return HStack(spacing:12) {
            Image(systemName:"car.side.fill").font(.headline).foregroundStyle(HospitalTheme.wine)
                .frame(width:42,height:42).background(HospitalTheme.rose,in:RoundedRectangle(cornerRadius:12,style:.continuous))
            VStack(alignment:.leading,spacing:3) {
                Text("Unidad \(unit.code)").font(.headline)
                Text(available ? "Lista para despacho" : "Las nuevas solicitudes quedan en espera").font(.caption).foregroundStyle(HospitalTheme.secondary)
            }
            Spacer(minLength:0)
            Text(DoctorTransportLabels.unit(unit.status)).font(.caption2.bold()).padding(.horizontal,8).padding(.vertical,4)
                .foregroundStyle(available ? Color(red:0.13,green:0.5,blue:0.3) : HospitalTheme.wine)
                .background(available ? HospitalTheme.green : HospitalTheme.rose,in:Capsule())
        }.modifier(ConsultationCardStyle()).accessibilityElement(children:.combine)
    }
    private var transportFormView: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {
                Text("Nueva solicitud de ambulancia").font(.title3.bold())
                Spacer()
                Button("Cancelar") { model.resetTransportForm() }.font(.subheadline.weight(.semibold)).tint(HospitalTheme.wine)
            }
            if let pending=model.pendingTransport {
                VStack(alignment:.leading,spacing:8) {
                    Label("Envío sin confirmar",systemImage:"exclamationmark.arrow.triangle.2.circlepath").font(.subheadline.bold())
                    Text("Reintenta la misma solicitud para evitar duplicados.").font(.footnote)
                    Text("\(pending.patientName) · \(pending.origin) → \(pending.destination)").font(.caption.weight(.semibold))
                }.foregroundStyle(HospitalTheme.wine).padding(14).frame(maxWidth:.infinity,alignment:.leading)
                    .background(HospitalTheme.rose,in:RoundedRectangle(cornerRadius:14,style:.continuous))
            }
            Group {
                patientStep("Paciente a trasladar", searchLabel:"Buscar paciente para trasladar", pendingName:model.pendingTransport?.patientName, pendingRecord:nil)
                Divider()
                VStack(alignment:.leading,spacing:14) {
                    ConsultationBlockHeader(letter:"2",icon:"map",title:"Traslado",subtitle:"Indica dónde se recoge al paciente y a dónde se le lleva.")
                    transportField("Origen (lugar de recogida)",text:$model.transportOrigin,placeholder:"Dirección o servicio de origen")
                    transportField("Destino",text:$model.transportDestination,placeholder:"Hospital, servicio o dirección de destino")
                    Text("Prioridad").font(.subheadline.weight(.semibold))
                    Picker("Prioridad",selection:$model.transportPriority) {
                        Text("Normal").tag("normal")
                        Text("Urgente").tag("urgente")
                    }.pickerStyle(.segmented)
                }
                Divider()
                VStack(alignment:.leading,spacing:14) {
                    ConsultationBlockHeader(letter:"3",icon:"phone",title:"Contacto y motivo",subtitle:"Persona a la que llamará el equipo de la ambulancia.")
                    transportField("Persona de contacto",text:$model.transportContact,placeholder:"Nombre del contacto")
                    transportField("Teléfono de contacto",text:$model.transportPhone,placeholder:"Teléfono",keyboard:.phonePad)
                    ConsultationNoteField(icon:"cross.case",title:"Motivo del traslado",placeholder:"Describe por qué el paciente necesita la ambulancia",text:$model.transportReason)
                }
            }.disabled(model.pendingTransport != nil)
            Button { confirmTransport=true } label: {
                Label(model.pendingTransport == nil ? "Revisar y solicitar" : "Reintentar el mismo envío",systemImage:"paperplane.fill").font(.headline).foregroundStyle(.white)
                    .frame(maxWidth:.infinity,minHeight:54)
                    .background(model.canRequestTransport ? AnyShapeStyle(LinearGradient.vinoDestacado) : AnyShapeStyle(HospitalTheme.secondary),in:RoundedRectangle(cornerRadius:16,style:.continuous))
            }.buttonStyle(.plain).disabled(!model.canRequestTransport)
        }.modifier(ConsultationCardStyle())
    }
    private func transportField(_ title:String,text:Binding<String>,placeholder:String,keyboard:UIKeyboardType = .default) -> some View {
        VStack(alignment:.leading,spacing:6) {
            Text(title).font(.subheadline.weight(.semibold))
            TextField(placeholder,text:text).keyboardType(keyboard).accessibilityLabel(title)
                .padding(14).background(HospitalTheme.background,in:RoundedRectangle(cornerRadius:12,style:.continuous))
        }
    }
    private func transportCard(_ item:DoctorTransportRequest) -> some View {
        let done=["despachada","finalizada"].contains(item.status), closed=["rechazada","cancelada"].contains(item.status)
        return VStack(alignment:.leading,spacing:10) {
            HStack(alignment:.top,spacing:12) {
                Image(systemName:"cross.case.fill").font(.headline).foregroundStyle(HospitalTheme.wine)
                    .frame(width:42,height:42).background(HospitalTheme.rose,in:RoundedRectangle(cornerRadius:12,style:.continuous))
                VStack(alignment:.leading,spacing:4) {
                    Text(item.patientName ?? item.contact_name).font(.headline)
                    Text(DoctorDate.display(item.requested_at)).font(.caption).foregroundStyle(HospitalTheme.secondary)
                }
                Spacer(minLength:0)
                Text(DoctorTransportLabels.status(item.status)).font(.caption2.bold()).padding(.horizontal,8).padding(.vertical,4)
                    .foregroundStyle(done ? Color(red:0.13,green:0.5,blue:0.3) : closed ? HospitalTheme.secondary : HospitalTheme.wine)
                    .background(done ? HospitalTheme.green : closed ? HospitalTheme.background : HospitalTheme.rose,in:Capsule())
            }
            Label("\(item.pickup_location) → \(item.destination ?? "Destino por confirmar")",systemImage:"map").font(.subheadline)
            if item.priority == "urgente" {
                choiceChip("Urgente",icon:"exclamationmark.triangle.fill",selected:true) {}.allowsHitTesting(false)
            }
            DisclosureGroup("Ver detalle del traslado") {
                VStack(alignment:.leading,spacing:12) {
                    detail("Motivo",item.reason)
                    detail("Contacto","\(item.contact_name) · \(item.contact_phone)")
                    if let reason=item.decision_reason { detail("Respuesta de administración",reason) }
                }.padding(.top,10)
            }.font(.subheadline.weight(.semibold)).tint(HospitalTheme.wine)
        }.modifier(ConsultationCardStyle())
    }
    private func choiceChip(_ title:String,icon:String,selected:Bool,action:@escaping () -> Void) -> some View {
        Button(action:action) {
            Label(title,systemImage:icon).font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? .white : HospitalTheme.wine)
                .padding(.horizontal,14).padding(.vertical,9)
                .background(selected ? AnyShapeStyle(LinearGradient.vinoDestacado) : AnyShapeStyle(HospitalTheme.rose),in:Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected,.isButton] : .isButton)
    }
    private func doctorEmpty(icon:String,title:String,text:String) -> some View {
        VStack(spacing:8) {
            Image(systemName:icon).font(.system(size:28,weight:.semibold)).foregroundStyle(HospitalTheme.wine)
                .frame(width:58,height:58).background(HospitalTheme.rose,in:Circle())
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(HospitalTheme.ink)
            Text(text).font(.footnote).foregroundStyle(HospitalTheme.secondary).multilineTextAlignment(.center)
        }.padding(20).frame(maxWidth:.infinity).background(.white,in:RoundedRectangle(cornerRadius:18,style:.continuous))
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
        VStack(alignment: .leading, spacing: 16) {
        if let reminder = model.alerts.first(where: { $0.read_at == nil && $0.title == "Tu próxima consulta está por comenzar" }) {
            HospitalCard {
                Label(reminder.title, systemImage: "bell.badge.fill").font(.headline).foregroundStyle(HospitalTheme.wine)
                Text(reminder.body).font(.subheadline)
                Button("Ver avisos") { navigate("notifications") }
            }
        }
        let today = model.dayAppointments
        let pending = model.agenda
        DoctorDashboardView(name: workspace.doctor_name, facility: workspace.facility_name,
            consultationCount: today.filter { !["cancelled", "rejected", "no_show"].contains($0.status) }.count,
            pendingCount: today.filter { ["scheduled","confirmed","in_progress"].contains($0.status) }.count,
            completedCount: today.filter { $0.status == "completed" }.count,
            nextAppointment: (pending.day + pending.upcoming).first { $0.status == "in_progress" || ($0.startDate ?? .distantPast) >= Date() },
            period: period,
            unreadCount: model.unreadAlerts,
            navigate: navigate)
        }
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
                    HospitalBadge(text: DoctorClinicalRules.statusLabel(appointment.status))
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
        VStack(alignment: .leading, spacing: 12) {
            ConsultationBlockHeader(icon: "person.crop.circle", title: "Paciente", subtitle: "Pacientes de tu agenda para la fecha elegida.")
            Menu {
                Picker("Paciente / turno", selection: Binding(get: { model.selectedAppointmentID }, set: { model.select($0) })) {
                    Text("Seleccionar paciente").tag(nil as UUID?)
                    ForEach(workspace.appointments) { appointment in
                        Text("\(appointment.patient_name) · \(appointment.ticket_number ?? appointment.record_number)")
                            .tag(Optional(appointment.id))
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Text(model.selectedAppointment.map { DoctorAssignedPatient.initials($0.patient_name) } ?? "?").font(.headline.bold()).foregroundStyle(HospitalTheme.wine)
                        .frame(width: 44, height: 44).background(HospitalTheme.rose, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Paciente / turno").font(.caption).foregroundStyle(HospitalTheme.secondary)
                        Text(model.selectedAppointment?.patient_name ?? "Seleccionar paciente").font(.subheadline.weight(.semibold)).foregroundStyle(HospitalTheme.ink)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down").font(.caption.bold()).foregroundStyle(HospitalTheme.wine)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }.accessibilityLabel("Paciente / turno")
            if let patient = model.selectedAppointment {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10, alignment: .topLeading)], alignment: .leading, spacing: 10) {
                    pickerTile("Edad", DoctorConsultationFields.age(patient.age))
                    pickerTile("Expediente", patient.record_number)
                    pickerTile("Consultorio", patient.room_code ?? "No publicado")
                    pickerTile("Duración", patient.duration_minutes.map { "\($0) minutos" } ?? "No publicada")
                    pickerTile("Turno", patient.ticket_number ?? "Sin turno asignado")
                    pickerTile("Teléfono", patient.phone ?? "No registrado")
                }
                detail("Especialidad solicitada", patient.specialty ?? "Cita directa de recepción; sin solicitud vinculada")
                detail("Motivo original", patient.reason ?? "Sin solicitud de atención vinculada")
                detail("Síntomas declarados", DoctorConsultationFields.symptoms(patient.symptoms))
                if let other = patient.other_symptoms { detail("Otros síntomas", other) }
            } else {
                Text("Selecciona un paciente de tu agenda.").font(.footnote).foregroundStyle(HospitalTheme.secondary)
            }
        }.modifier(ConsultationCardStyle())
    }
    private func pickerTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(HospitalTheme.secondary)
            Text(value).font(.footnote.weight(.semibold)).foregroundStyle(HospitalTheme.ink)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    private func consultation(_ workspace: DoctorWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let appointment = model.selectedAppointment {
                consultationWorkspace(workspace, appointment)
            } else {
                DoctorConsultationAgendaView(day: $model.day, appointments: workspace.appointments,
                    search: search, period: period, demonstration: false, statusFilter: $model.statusFilter,
                    select: { id in
                        model.select(id)
                        if screenID == "agenda" { navigate("consultation") }
                        Task { await model.startConsultation() }
                    })
                    .onChange(of: model.day) { _, _ in model.select(nil); Task { await model.refresh() } }
            }
        }
    }

    // MARK: Flujo de consulta: detalle → apertura → bloques A–C → guardado → finalización

    @ViewBuilder
    private func consultationWorkspace(_ workspace: DoctorWorkspace, _ appointment: DoctorAppointment) -> some View {
        Button { if model.hasUnsavedChanges && model.canEditConsultation { confirmLeave = true } else { model.select(nil) } } label: {
            Label("Volver a la agenda", systemImage: "chevron.left").font(.subheadline.weight(.semibold))
        }.tint(HospitalTheme.wine)
        ConsultationPatientCard(appointment: appointment, patientCode: patientCode(appointment))
        if appointment.encounter_id == nil {
            ConsultationAppointmentCard(appointment: appointment, doctorName: workspace.doctor_name, openedAt: nil)
            VStack(alignment: .leading, spacing: 12) {
                ConsultationBlockHeader(icon: "list.bullet.clipboard", title: "Síntomas reportados", subtitle: "Podrás revisarlos y precisarlos al abrir la consulta")
                ConsultationReportedSymptoms(symptoms: ConsultationFormat.symptoms(appointment), other: appointment.other_symptoms?.trimmingCharacters(in: .whitespacesAndNewlines))
            }.modifier(ConsultationCardStyle())
            let blocker = DoctorConsultationFields.openingBlocker(appointment)
            Button { Task { await model.startConsultation() } } label: {
                Label("ABRIR CONSULTA MÉDICA", systemImage: "stethoscope").font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(blocker == nil ? AnyShapeStyle(LinearGradient.vinoDestacado) : AnyShapeStyle(HospitalTheme.secondary), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }.buttonStyle(.plain).disabled(blocker != nil)
            if let blocker { HospitalNotice(text: blocker) }
        } else if let encounter = model.activeConsultation {
            if model.canEditConsultation {
                saveStatusBar
                if let server = model.conflictNote { conflictCard(server) }
                ConsultationAppointmentCard(appointment: appointment, doctorName: workspace.doctor_name, openedAt: DoctorDate.parse(encounter.started_at))
                DisclosureGroup { patientChart(workspace, showPicker: false).padding(.top, 12) } label: {
                    Label("Expediente e historial previo", systemImage: "folder.badge.person.crop").font(.headline).foregroundStyle(HospitalTheme.ink)
                }.tint(HospitalTheme.wine).modifier(ConsultationCardStyle())
                physicalDataForm
                medicalEvaluationForm(appointment)
                additionalServices
                finishPanel
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Consulta finalizada", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(HospitalTheme.wine)
                    Text("La información quedó registrada en el expediente y en el historial del paciente. Ya no puede editarse desde la app.")
                        .font(.footnote).foregroundStyle(HospitalTheme.secondary)
                    Divider()
                    consultationRecord(encounter)
                }.modifier(ConsultationCardStyle())
            }
        } else if model.loadingChart {
            ProgressView("Cargando la consulta…").frame(maxWidth: .infinity)
        } else {
            HospitalNotice(text: "No se pudo cargar la consulta abierta. Actualiza para continuar; lo escrito no se envía hasta guardar.")
            Button("Actualizar consulta", systemImage: "arrow.clockwise") { Task { await model.loadChart() } }
        }
    }

    /// patients.patient_code solo llega cuando se aplica supabase/doctor-consultation-six-fields.sql; sin él se muestra el expediente.
    private func patientCode(_ appointment: DoctorAppointment) -> String? {
        appointment.patient_code ?? (model.contextChart?.patient.id == appointment.patient_id ? model.contextChart?.patient.patient_code : nil)
    }

    private var saveStatusBar: some View {
        let (text, icon): (String, String) = {
            switch model.saveState {
            case .saving: return ("Guardando…", "arrow.triangle.2.circlepath")
            case .failed(let reason): return ("Error al guardar · \(reason) Lo escrito sigue en pantalla.", "exclamationmark.triangle.fill")
            default: return model.hasUnsavedChanges ? ("Cambios pendientes de guardar", "pencil.circle") :
                model.saveState == .saved ? ("Guardado correctamente", "checkmark.circle.fill") : ("Sin cambios pendientes", "checkmark.circle")
            }
        }()
        return HStack(spacing: 10) {
            Image(systemName: icon)
            Text(text).font(.footnote.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Guardar avances") { Task { await model.saveConsultation() } }
                .font(.footnote.bold()).disabled(!model.hasUnsavedChanges || model.saving)
        }.foregroundStyle(HospitalTheme.wine).padding(12)
            .background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .contain)
    }

    private func conflictCard(_ server: DoctorConsultation) -> some View {
        HospitalCard {
            Label("Otra sesión guardó esta consulta", systemImage: "exclamationmark.arrow.triangle.2.circlepath").font(.headline).foregroundStyle(HospitalTheme.wine)
            Text("Esta es la versión guardada en el expediente. Elige cuál conservar; nada se sobrescribe sin tu confirmación.").font(.footnote)
            detail("Síntomas guardados", server.subjective ?? "Sin registrar")
            detail("Diagnóstico guardado", server.assessment ?? "Sin registrar")
            detail("Observaciones guardadas", server.objective ?? "Sin registrar")
            Button("Usar la versión guardada") { Task { await model.resolveConflict(keepMine: false) } }.buttonStyle(.bordered)
            Button("Conservar lo que escribí y guardar") { Task { await model.resolveConflict(keepMine: true) } }.buttonStyle(HospitalPrimaryButtonStyle())
        }
    }

    /// Bloque A. Peso, altura y temperatura (public.vital_signs, rangos de doctor_native_save). Las medidas
    /// antiguas que ya no se capturan permanecen en el borrador y se reenvían sin cambios.
    private var physicalDataForm: some View {
        let issues = model.vitalIssues
        return VStack(alignment: .leading, spacing: 16) {
            ConsultationBlockHeader(letter: "A", icon: "figure.stand", title: "Datos físicos", subtitle: "Registra solo lo que midas; los campos vacíos no se guardan.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)], spacing: 12) {
                ForEach(DoctorClinicalRules.vitals) { vital in
                    ConsultationMeasureField(vital: vital, icon: measureIcon(vital.key), value: vitalBinding(vital.key), issue: issues[vital.key])
                }
            }
            if let bmi = DoctorClinicalRules.bmi(model.draft.vitals) {
                HStack {
                    Label("IMC calculado", systemImage: "function").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(bmi) kg/m²").font(.subheadline.monospacedDigit().bold())
                }.foregroundStyle(HospitalTheme.wine).padding(12)
                    .background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHint("Calculado con el peso y la altura; no se guarda como medición")
            }
        }.modifier(ConsultationCardStyle())
    }

    private func measureIcon(_ key: String) -> String {
        ["weight_kg": "scalemass", "height_cm": "ruler", "temperature_c": "thermometer.medium"][key] ?? "number"
    }

    private func vitalBinding(_ key: String) -> Binding<String> {
        Binding(get: { model.draft.vitals[key] ?? "" }, set: { value in
            if value.isEmpty { model.draft.vitals.removeValue(forKey: key) } else { model.draft.vitals[key] = value }
        })
    }

    /// Bloque B. Síntomas → subjective, Diagnóstico → assessment (y public.diagnoses), Observaciones → objective.
    private func medicalEvaluationForm(_ appointment: DoctorAppointment) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ConsultationBlockHeader(letter: "B", icon: "stethoscope", title: "Evaluación médica", subtitle: "Los cuatro campos son obligatorios para finalizar la consulta.")
            // Síntomas que envió el paciente: referencia de solo lectura (appointment_requests); no se copian ni se editan.
            VStack(alignment: .leading, spacing: 8) {
                Label("Reportados por el paciente · solo lectura", systemImage: "lock.fill").font(.caption.weight(.semibold)).foregroundStyle(HospitalTheme.secondary)
                ConsultationReportedSymptoms(symptoms: ConsultationFormat.symptoms(appointment), other: appointment.other_symptoms?.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            ConsultationNoteField(icon: "list.bullet.clipboard", title: "Síntomas actuales",
                placeholder: "Síntomas que encuentras en la consulta, cuándo iniciaron y cómo han evolucionado", text: $model.draft.subjective,
                hint: "Lo que registras tú; los síntomas del paciente se conservan arriba sin cambios.")
            Divider()
            ConsultationNoteField(icon: "note.text", title: "Exploración y observaciones",
                placeholder: "Hallazgos de la exploración física y observaciones clínicas", text: $model.draft.objective)
            Divider()
            ConsultationNoteField(icon: "cross.case", title: "Diagnóstico",
                placeholder: "Diagnóstico principal y, si aplica, diagnósticos adicionales", text: $model.draft.assessment)
            Divider()
            ConsultationNoteField(icon: "cross.vial", title: "Plan de tratamiento",
                placeholder: "Tratamiento, indicaciones y seguimiento", text: $model.draft.plan)
        }.modifier(ConsultationCardStyle())
    }

    /// Bloque C. Formularios existentes de laboratorio y receta, abiertos sin salir de la consulta.
    private var additionalServices: some View {
        VStack(alignment: .leading, spacing: 14) {
            ConsultationBlockHeader(letter: "C", icon: "square.grid.2x2", title: "Servicios adicionales", subtitle: "Opcionales. Quedan asociados a esta consulta.")
            ConsultationServiceButton(icon: "testtube.2", title: "Solicitar exámenes",
                subtitle: "Elige pruebas del catálogo de laboratorio y revísalas antes de enviarlas.",
                badge: model.pendingLabs != nil ? "Envío pendiente de confirmar" : nil) { clinicalSheet = .labs }
            ConsultationServiceButton(icon: "pills.fill", title: "Recetar medicamentos",
                subtitle: "Añade uno o varios medicamentos y revisa la receta antes de emitirla.",
                badge: model.rxLines.isEmpty ? nil : "\(model.rxLines.count) medicamento(s) sin emitir") { clinicalSheet = .prescription }
        }.modifier(ConsultationCardStyle())
    }

    private var finishPanel: some View {
        let blockers = model.finishBlockers
        return VStack(alignment: .leading, spacing: 12) {
            if blockers.isEmpty {
                Label("Todo listo para finalizar", systemImage: "checkmark.circle.fill").font(.subheadline.bold())
                    .foregroundStyle(Color(red: 0.13, green: 0.5, blue: 0.3))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Para finalizar falta", systemImage: "checklist").font(.subheadline.bold())
                    ForEach(blockers, id: \.self) { Label($0, systemImage: "circle").font(.footnote) }
                }.foregroundStyle(HospitalTheme.wine).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Button { Task { await model.saveConsultation() } } label: {
                Label("Guardar consulta", systemImage: "square.and.arrow.down").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            }.buttonStyle(.bordered).tint(HospitalTheme.wine).disabled(model.saving || !model.draft.canSave)
            Button { confirmFinish = true } label: {
                Label("FINALIZAR CONSULTA", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(blockers.isEmpty ? AnyShapeStyle(LinearGradient.vinoDestacado) : AnyShapeStyle(HospitalTheme.secondary), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }.buttonStyle(.plain).disabled(!blockers.isEmpty || model.saving)
                .accessibilityHint(blockers.isEmpty ? "Pide confirmación antes de cerrar la consulta" : "Completa los campos obligatorios")
        }.modifier(ConsultationCardStyle())
    }

    private var clinicalSheetContent: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let appointment = model.selectedAppointment {
                        Label("\(appointment.patient_name) · Expediente \(appointment.record_number)", systemImage: "person.crop.circle")
                            .font(.subheadline.bold()).foregroundStyle(HospitalTheme.wine)
                    }
                    if model.saving { ProgressView("Enviando…").frame(maxWidth: .infinity) }
                    if let error = model.error { HospitalNotice(text: error) }
                    if let confirmation = model.confirmation { Label(confirmation, systemImage: "checkmark.circle.fill").font(.footnote.bold()).foregroundStyle(HospitalTheme.wine) }
                    if clinicalSheet == .labs { labSelectionView }
                    else if let workspace = model.workspace { prescriptionForm(workspace) }
                }.padding(18).disabled(model.saving)
            }
            .background(HospitalTheme.background)
            .navigationTitle(clinicalSheet == .labs ? "Solicitar exámenes" : "Recetar medicamento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Volver a la consulta") { clinicalSheet = nil } } }
            .confirmationDialog("¿Enviar los exámenes seleccionados al laboratorio?", isPresented: $confirmSheetLabs, titleVisibility: .visible) {
                Button("Confirmar exámenes") { Task { await model.issueSelectedLabs() } }
                Button("Seguir editando", role: .cancel) { }
            } message: { Text(selectedLabsSummary) }
            .confirmationDialog("¿Emitir esta receta?", isPresented: $confirmPrescription, titleVisibility: .visible) {
                Button("Confirmar y emitir receta") { Task { await model.issuePrescription() } }
                Button("Seguir editando", role: .cancel) { }
            } message: { Text(model.rxLines.map { "\($0.medication.label): \($0.dose) \($0.unit) cada \($0.frequency) h, \($0.days) días" }.joined(separator: "\n")) }
        }
        .task { if clinicalSheet == .labs && model.labCatalog.isEmpty { await model.loadLabCatalog() } }
    }

    private var selectedLabsSummary: String {
        let names = model.labCatalog.filter { model.selectedLabIDs.contains($0.id) }.map(\.name)
        return (names.isEmpty ? "" : names.joined(separator: ", ") + ". ") + "Las órdenes quedarán asociadas a esta consulta. El laboratorio registrará y validará los resultados."
    }

    private func laboratory(_ workspace: DoctorWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.canEditConsultation || model.pendingLabs != nil {
                labSelectionView
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ConsultationBlockHeader(icon: "testtube.2", title: "Solicitar exámenes", subtitle: "Las órdenes se emiten dentro de una consulta abierta.")
                    Text("Este paciente no tiene una consulta tuya abierta. Iníciala desde su cita en Agenda para emitir una orden.")
                        .font(.footnote).foregroundStyle(HospitalTheme.secondary)
                    Button("Ir a consulta", systemImage: "cross.case") { navigate("consultation") }.buttonStyle(.bordered).tint(HospitalTheme.wine)
                }.modifier(ConsultationCardStyle())
            }
            VStack(alignment: .leading, spacing: 12) {
                ConsultationBlockHeader(icon: "doc.text.magnifyingglass", title: "Exámenes y resultados del paciente",
                    subtitle: "Resultados autorizados de este expediente, sin limitarse a la agenda del día.")
                if model.patientLabsLoading { ProgressView("Cargando exámenes…").frame(maxWidth: .infinity) }
                if let error=model.patientLabsError {
                    HospitalNotice(text:error)
                    Button("Reintentar laboratorios") { Task { await model.loadPatientLabs() } }.tint(HospitalTheme.wine)
                }
                if model.patientLabs.isEmpty && !model.patientLabsLoading && model.patientLabsError == nil {
                    doctorEmpty(icon: "testtube.2", title: "Sin exámenes", text: "Este paciente todavía no tiene exámenes registrados.")
                }
                ForEach(model.patientLabs) { order in labOrderCard(order) }
                if model.patientLabPage?.has_more == true {
                    Button("Cargar más exámenes") { Task { await model.loadPatientLabs(more:true) } }.frame(maxWidth: .infinity).disabled(model.patientLabsLoading).tint(HospitalTheme.wine)
                }
            }
        }
    }

    private var labSelectionView: some View {
        let categories = Array(Set(model.labCatalog.map { $0.category ?? "Sin categoría" })).sorted()
        let selected = model.labCatalog.filter { model.selectedLabIDs.contains($0.id) }
        return VStack(alignment: .leading, spacing: 16) {
            ConsultationBlockHeader(letter: "1", icon: "testtube.2", title: "Elige los exámenes", subtitle: "Toca para seleccionar. Hasta 30 por envío.")
            if model.labCatalogLoading { ProgressView("Cargando catálogo…").frame(maxWidth: .infinity) }
            if let error=model.labCatalogError {
                HospitalNotice(text:error)
                Button("Reintentar catálogo") { Task { await model.loadLabCatalog() } }.tint(HospitalTheme.wine)
            }
            Group {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(HospitalTheme.wine)
                    TextField("Buscar exámenes", text: $model.labQuery).autocorrectionDisabled().accessibilityLabel("Buscar exámenes")
                    if !model.labQuery.isEmpty {
                        Button { model.labQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(HospitalTheme.secondary) }.accessibilityLabel("Borrar búsqueda")
                    }
                }.padding(.horizontal, 14).frame(minHeight: 48)
                    .background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        choiceChip("Todas", icon: "square.grid.2x2", selected: model.labCategory == "all") { model.labCategory = "all" }
                        ForEach(categories, id: \.self) { category in
                            choiceChip(category, icon: "drop", selected: model.labCategory == category) { model.labCategory = category }
                        }
                    }.padding(.vertical, 2)
                }.accessibilityLabel("Categoría de examen")
                if model.filteredLabTests.isEmpty && !model.labCatalogLoading {
                    Text(model.labCatalog.isEmpty ? "No hay exámenes activos. Actualiza el catálogo o contacta al laboratorio." : "No hay exámenes que coincidan con la búsqueda.")
                        .font(.footnote).foregroundStyle(HospitalTheme.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                    ForEach(model.filteredLabTests) { test in
                        let isSelected = model.selectedLabIDs.contains(test.id)
                        Button {
                            if isSelected { model.selectedLabIDs.remove(test.id) }
                            else if model.selectedLabIDs.count<30 { model.selectedLabIDs.insert(test.id) }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle").font(.title3)
                                    .foregroundStyle(isSelected ? HospitalTheme.wine : HospitalTheme.secondary.opacity(0.6))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(test.name).font(.subheadline.bold()).foregroundStyle(HospitalTheme.ink).multilineTextAlignment(.leading)
                                    Text(test.category ?? "Sin categoría").font(.caption).foregroundStyle(HospitalTheme.secondary)
                                }
                                Spacer(minLength: 0)
                            }.padding(12).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                                .background(isSelected ? HospitalTheme.rose : .white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(isSelected ? HospitalTheme.wine : HospitalTheme.rose, lineWidth: isSelected ? 1.5 : 1))
                        }.buttonStyle(.plain).accessibilityLabel("Seleccionar \(test.name)").accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                Divider()
                ConsultationBlockHeader(letter: "2", icon: "list.bullet.clipboard", title: "Resumen y motivo",
                    subtitle: "\(model.selectedLabIDs.count) \(model.selectedLabIDs.count == 1 ? "examen seleccionado" : "exámenes seleccionados")")
                if selected.isEmpty {
                    Text("Aún no has seleccionado exámenes.").font(.footnote).foregroundStyle(HospitalTheme.secondary)
                } else {
                    ConsultationFlowLayout(spacing: 6) {
                        ForEach(selected) { test in
                            Button { model.selectedLabIDs.remove(test.id) } label: {
                                Label(test.name, systemImage: "xmark").font(.caption.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
                                    .padding(.horizontal, 10).padding(.vertical, 6).background(HospitalTheme.rose, in: Capsule())
                            }.buttonStyle(.plain).accessibilityLabel("Quitar \(test.name)")
                        }
                    }
                }
                ConsultationNoteField(icon: "text.bubble", title: "Motivo e indicaciones clínicas", placeholder: "Motivo clínico e indicaciones para el laboratorio", text: $model.instructions)
            }.disabled(model.pendingLabs != nil)
            if let pending=model.pendingLabs {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Envío sin confirmar", systemImage: "exclamationmark.arrow.triangle.2.circlepath").font(.subheadline.bold())
                    Text("Se reintentará exactamente la misma selección, sin duplicar órdenes.").font(.footnote)
                    Text("\(pending.patientName) · \(pending.recordNumber ?? "Expediente no disponible")").font(.caption.weight(.semibold))
                    Text(pending.reason).font(.caption).lineLimit(3)
                }.foregroundStyle(HospitalTheme.wine).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Button { if clinicalSheet == .labs { confirmSheetLabs = true } else { confirmLabs = true } } label: {
                Label(model.pendingLabs == nil ? "Revisar y enviar exámenes" : "Reintentar el mismo envío", systemImage: "paperplane.fill").font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(model.canIssueLabs ? AnyShapeStyle(LinearGradient.vinoDestacado) : AnyShapeStyle(HospitalTheme.secondary), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }.buttonStyle(.plain).disabled(!model.canIssueLabs)
        }.modifier(ConsultationCardStyle())
    }
    private var ownLabOrdersView: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Label("Mis órdenes de laboratorio", systemImage: "testtube.2").font(.headline).foregroundStyle(HospitalTheme.ink)
                Spacer()
                if model.ownLabsLoading { ProgressView().controlSize(.small) }
                Button { Task { await model.loadOwnLabOrders() } } label: {
                    Image(systemName: "arrow.clockwise").font(.subheadline.bold()).foregroundStyle(HospitalTheme.wine)
                        .frame(width: 36, height: 36).background(HospitalTheme.rose, in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("Actualizar órdenes")
            }
            if let pending=model.pendingLabs {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Envío sin confirmar · \(pending.patientName)", systemImage: "exclamationmark.arrow.triangle.2.circlepath").font(.subheadline.bold()).foregroundStyle(HospitalTheme.wine)
                    Text("\(pending.tests.count) exámenes · \(pending.reason)").font(.footnote).lineLimit(3)
                    Button("Reintentar el mismo envío") { confirmLabs=true }.buttonStyle(HospitalPrimaryButtonStyle())
                }.modifier(ConsultationCardStyle())
            }
            if let error=model.ownLabsError { HospitalNotice(text:error) }
            if model.ownLabOrders.isEmpty && !model.ownLabsLoading && model.ownLabsError == nil {
                doctorEmpty(icon: "testtube.2", title: "Sin órdenes", text: "Todavía no has solicitado exámenes de laboratorio.")
            }
            ForEach(model.ownLabOrders) { labOrderCard($0) }
            if model.ownLabPage?.has_more == true { Button("Cargar más órdenes") { Task { await model.loadOwnLabOrders(more:true) } }.frame(maxWidth: .infinity).tint(HospitalTheme.wine) }
            Label("Busca un paciente abajo para revisar su expediente o solicitar exámenes desde una consulta abierta.", systemImage: "info.circle")
                .font(.footnote).foregroundStyle(HospitalTheme.secondary)
        }
    }
    private func labOrderCard(_ order:DoctorPatientLab) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: order.result_summary == nil ? "testtube.2" : "checkmark.seal.fill").font(.headline)
                    .foregroundStyle(order.result_summary == nil ? HospitalTheme.wine : Color(red: 0.13, green: 0.5, blue: 0.3))
                    .frame(width: 42, height: 42).background(order.result_summary == nil ? HospitalTheme.rose : HospitalTheme.green, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(order.test_name).font(.headline).foregroundStyle(HospitalTheme.ink)
                    if let patient=order.patient_name { Text(patient).font(.subheadline).foregroundStyle(HospitalTheme.ink.opacity(0.85)) }
                    Text(DoctorDate.display(order.ordered_at)).font(.caption).foregroundStyle(HospitalTheme.secondary)
                }
                Spacer(minLength: 0)
                if order.status == "pendiente" { ClinicalLabStateBadge(state:.pending) }
                else if order.status == "en_proceso" { ClinicalLabStateBadge(state:.processing) }
                else if order.status == "completado" { ClinicalLabStateBadge(state:.completed) }
                else { Text(status(order.status)).font(.caption) }
            }
            DisclosureGroup("Ver detalle del examen") {
                VStack(alignment:.leading,spacing:10) {
                    if let record=order.record_number { detail("Expediente",record) }
                    detail("Motivo e indicaciones",order.reason)
                    if let summary=order.result_summary {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Resultado validado y publicado").font(.caption.weight(.semibold)).foregroundStyle(Color(red: 0.13, green: 0.5, blue: 0.3))
                            Text(summary).font(.subheadline).foregroundStyle(HospitalTheme.ink)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(HospitalTheme.green, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        ForEach(Array((order.parameters ?? []).enumerated()),id:\.offset) { _,parameter in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(parameter.label).font(.caption.weight(.semibold)).foregroundStyle(HospitalTheme.secondary)
                                    Spacer()
                                    Text([parameter.value,parameter.unit].compactMap { $0 }.joined(separator:" ")).font(.subheadline.bold().monospacedDigit()).foregroundStyle(HospitalTheme.ink)
                                }
                                if let reference=parameter.reference, !reference.isEmpty { Text("Referencia del laboratorio: \(reference)").font(.caption2).foregroundStyle(HospitalTheme.secondary) }
                                if let observation=parameter.observation, !observation.isEmpty { Text("Observación: \(observation)").font(.caption2).foregroundStyle(HospitalTheme.secondary) }
                            }.padding(10).background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        if let date=order.published_at { Label("Publicado \(DoctorDate.display(date))", systemImage: "calendar").font(.caption).foregroundStyle(HospitalTheme.secondary) }
                    } else {
                        Label("El laboratorio está procesando la orden o aún no ha publicado un resultado validado.", systemImage: "hourglass").font(.footnote).foregroundStyle(HospitalTheme.secondary)
                    }
                }.padding(.top,10)
            }.font(.subheadline.weight(.semibold)).tint(HospitalTheme.wine)
        }.modifier(ConsultationCardStyle())
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
    /// Formulario de receta existente (doctor_native_prescribe): catálogo real, varias líneas y revisión antes de emitir.
    private func prescriptionForm(_ workspace: DoctorWorkspace) -> some View {
        let medications = (workspace.medications ?? []).filter { medicationQuery.isEmpty || $0.label.localizedCaseInsensitiveContains(medicationQuery) }
        let chosen = (workspace.medications ?? []).first { $0.id == model.rxMedication }
        return VStack(alignment: .leading, spacing: 16) {
            if model.canEditConsultation {
                VStack(alignment: .leading, spacing: 14) {
                    ConsultationBlockHeader(letter: "1", icon: "pills.fill", title: "Medicamento", subtitle: "Busca en el catálogo activo del hospital.")
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(HospitalTheme.wine)
                        TextField("Buscar en el catálogo de medicamentos", text: $medicationQuery).autocorrectionDisabled()
                        if !medicationQuery.isEmpty {
                            Button { medicationQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(HospitalTheme.secondary) }.accessibilityLabel("Borrar búsqueda")
                        }
                    }.padding(.horizontal, 14).frame(minHeight: 48)
                        .background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Menu {
                        Picker("Medicamento y concentración",selection:$model.rxMedication) {
                            Text("Seleccionar medicamento").tag(nil as UUID?)
                            ForEach(medications) { Text($0.label).tag(Optional($0.id)) }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "pills").font(.headline).foregroundStyle(HospitalTheme.wine)
                                .frame(width: 40, height: 40).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Medicamento y concentración").font(.caption).foregroundStyle(HospitalTheme.secondary)
                                Text(chosen?.label ?? "Seleccionar medicamento").font(.subheadline.weight(.semibold)).foregroundStyle(HospitalTheme.ink).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.up.chevron.down").font(.caption.bold()).foregroundStyle(HospitalTheme.wine)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(HospitalTheme.rose, lineWidth: 1.5))
                    }.accessibilityLabel("Medicamento y concentración")
                    if (workspace.medications ?? []).isEmpty { Text("No hay medicamentos activos publicados en el catálogo.").font(.footnote).foregroundStyle(HospitalTheme.secondary) }
                    else if medications.isEmpty { Text("Ningún medicamento coincide con la búsqueda.").font(.footnote).foregroundStyle(HospitalTheme.secondary) }
                    Divider()
                    ConsultationBlockHeader(letter: "2", icon: "list.bullet.rectangle", title: "Indicación", subtitle: "Dosis, vía, frecuencia, duración e instrucciones.")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10, alignment: .top)], spacing: 10) {
                        rxField("Dosis", $model.rxDose, placeholder: "Ej. 500", keyboard: .decimalPad)
                        rxField("Unidad (mg, ml…)", $model.rxUnit, placeholder: "mg, ml, tableta")
                        rxField("Cada cuántas horas", $model.rxFrequency, placeholder: "Ej. 8", keyboard: .numberPad, unit: "h")
                        rxField("Duración (días)", $model.rxDays, placeholder: "Ej. 5", keyboard: .numberPad, unit: "días")
                        rxField("Cantidad total", $model.rxQuantity, placeholder: "Ej. 15", keyboard: .numberPad, unit: "u.")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Vía de administración").font(.caption.weight(.semibold)).foregroundStyle(HospitalTheme.secondary)
                        Picker("Vía de administración",selection:$model.rxRoute) { Text("Oral").tag("oral"); Text("Inyectable").tag("inyectable") }.pickerStyle(.segmented)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Instrucciones para el paciente").font(.caption.weight(.semibold)).foregroundStyle(HospitalTheme.secondary)
                        TextField("Cómo y cuándo tomarlo", text: $model.rxInstructions, axis: .vertical).lineLimit(2...5)
                            .padding(12).background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityLabel("Instrucciones para el paciente")
                    }
                    Button { model.addMedication() } label: {
                        Label("Añadir a la receta", systemImage: "plus.circle.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.bordered).tint(HospitalTheme.wine)
                }.modifier(ConsultationCardStyle())
                VStack(alignment: .leading, spacing: 12) {
                    ConsultationBlockHeader(letter: "3", icon: "signature", title: "Revisión de la receta · \(model.rxLines.count) medicamento(s)", subtitle: "Revisa cada línea antes de emitir.")
                    if model.rxLines.isEmpty {
                        Text("Añade uno o varios medicamentos para revisarlos antes de emitir.").font(.footnote).foregroundStyle(HospitalTheme.secondary)
                    }
                    ForEach(model.rxLines) { line in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "pills.fill").foregroundStyle(HospitalTheme.wine)
                                .frame(width: 36, height: 36).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment:.leading,spacing:5) {
                                Text(line.medication.label).font(.subheadline.bold())
                                ConsultationFlowLayout(spacing: 5) {
                                    ForEach(["\(line.dose.description) \(line.unit)", "vía \(line.route)", "cada \(line.frequency) h", "\(line.days) días", "\(line.quantity) unidades"], id: \.self) { item in
                                        Text(item).font(.caption2.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
                                            .padding(.horizontal, 8).padding(.vertical, 3).background(HospitalTheme.rose, in: Capsule())
                                    }
                                }
                                Text(line.instructions).font(.caption).foregroundStyle(HospitalTheme.secondary)
                            }
                            Spacer(minLength: 0)
                            Button(role: .destructive) { model.rxLines.removeAll { $0.id == line.id } } label: {
                                Image(systemName: "trash").font(.subheadline)
                            }.accessibilityLabel("Retirar de esta receta")
                        }.padding(12).background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    Button { confirmPrescription = true } label: {
                        Label("Revisar y emitir receta", systemImage: "signature").font(.headline).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(model.rxLines.isEmpty ? AnyShapeStyle(HospitalTheme.secondary) : AnyShapeStyle(LinearGradient.vinoDestacado), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }.buttonStyle(.plain).disabled(model.rxLines.isEmpty)
                }.modifier(ConsultationCardStyle())
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ConsultationBlockHeader(icon: "pills.fill", title: "Emitir receta", subtitle: "Las recetas se emiten dentro de una consulta abierta.")
                    Text("Abre la consulta desde la agenda para emitir recetas.").font(.footnote).foregroundStyle(HospitalTheme.secondary)
                    Button("Ir a la agenda", systemImage: "calendar") { navigate("consultation") }.buttonStyle(.bordered).tint(HospitalTheme.wine)
                }.modifier(ConsultationCardStyle())
            }
        }
    }

    private func rxField(_ title: String, _ text: Binding<String>, placeholder: String, keyboard: UIKeyboardType = .default, unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(HospitalTheme.secondary)
            HStack(spacing: 6) {
                TextField(placeholder, text: text).keyboardType(keyboard).font(.body.monospacedDigit()).accessibilityLabel(title)
                if let unit { Text(unit).font(.caption.bold()).foregroundStyle(HospitalTheme.wine) }
            }.padding(12).background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func prescriptions(_ workspace: DoctorWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label("RECETAS", systemImage: "pills.fill").font(.caption2.weight(.heavy)).tracking(1.2).opacity(0.85)
                Text("Receta médica").font(.title2.bold())
                Text("Elige el paciente de tu agenda; la receta se emite dentro de su consulta abierta.").font(.subheadline).opacity(0.9)
            }.foregroundStyle(.white).padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient.vinoDestacado, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            patientPicker(workspace)
            prescriptionForm(workspace)
                .confirmationDialog("¿Emitir esta receta?", isPresented: $confirmPrescription, titleVisibility: .visible) {
                    Button("Confirmar y emitir receta") { Task { await model.issuePrescription() } }
                    Button("Seguir editando", role: .cancel) { }
                }
            Label("Recetas de mis consultas de este paciente", systemImage: "doc.text").font(.headline).foregroundStyle(HospitalTheme.ink)
            if (model.contextChart?.prescriptions ?? []).isEmpty {
                doctorEmpty(icon: "pills", title: "Sin recetas", text: model.selectedAppointment == nil ? "Selecciona un paciente para ver sus recetas." : "Todavía no has emitido recetas para este paciente.")
            }
            ForEach(model.contextChart?.prescriptions ?? []) { prescription in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(prescription.code, systemImage: "doc.text.fill").font(.headline).foregroundStyle(HospitalTheme.ink)
                        Spacer()
                        Text(prescription.status == "pendiente" ? "Pendiente de entrega" : prescription.status).font(.caption2.bold()).foregroundStyle(HospitalTheme.wine)
                            .padding(.horizontal, 8).padding(.vertical, 4).background(HospitalTheme.rose, in: Capsule())
                    }
                    Text(DoctorDate.display(prescription.issued_at)).font(.caption).foregroundStyle(HospitalTheme.secondary)
                    ForEach(Array(prescription.lines.enumerated()),id: \.offset) { _, line in Label(line, systemImage: "pills").font(.footnote) }
                }.modifier(ConsultationCardStyle())
            }
        }
    }
    private func consultationRecord(_ record: DoctorConsultation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(DoctorDate.display(record.started_at)).font(.subheadline.weight(.semibold))
            HospitalBadge(text: status(record.status))
            detail("Síntomas actuales", record.subjective ?? "Sin registrar")
            detail("Diagnóstico", record.assessment ?? "Sin registrar")
            if let code = record.diagnosis_code, !code.isEmpty { detail("Código diagnóstico", code) }
            detail("Exploración y observaciones", record.objective ?? "Sin registrar")
            if let plan = record.plan, !plan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { detail("Plan de tratamiento", plan) }
            ForEach(DoctorClinicalRules.recordedVitals) { vital in
                if let value = record.vitals?[vital.key] { detail("\(vital.label) (\(vital.unit))", value) }
            }
            if let bmi = DoctorClinicalRules.bmi(record.vitals ?? [:]) { detail("IMC (calculado)", "\(bmi) kg/m²") }
        }
    }

    private func notifications(_ values: [DoctorNotification]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tu centro de avisos").font(.title2.bold())
            Text("\(model.unreadAlerts) sin leer · Citas y novedades del hospital").font(.subheadline).foregroundStyle(HospitalTheme.secondary)
            Button("Activar recordatorios en este iPhone", systemImage: "bell.badge") { Task { await model.enableReminders() } }
            Text("Aviso 15 minutos antes para citas sincronizadas. Actualiza la app si la agenda cambia.").font(.caption).foregroundStyle(HospitalTheme.secondary)
            if let message = model.notificationMessage { HospitalNotice(text: message) }
            if let error = model.alertsError { HospitalNotice(text: error) }
            Button("Actualizar avisos", systemImage: "arrow.clockwise") { Task { await model.refreshAlerts() } }
            let notifications = values.sorted { $0.created_at > $1.created_at }.filter { matches($0.title + " " + $0.body) }
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
            if model.alertsHaveMore { Button("Cargar más avisos") { Task { await model.refreshAlerts(more: true) } } }
        }
    }

    private func field(_ title: String, text: Binding<String>, required: Bool = false, hint: String? = nil) -> some View {
        let empty = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title).font(.subheadline.weight(.medium))
                if required {
                    Text(empty ? "Obligatorio para finalizar" : "Completo").font(.caption2.bold())
                        .foregroundStyle(empty ? HospitalTheme.wine : HospitalTheme.secondary)
                }
            }
            TextField(title, text: text, axis: .vertical).lineLimit(3...10)
                .padding(12).background(required ? HospitalTheme.background : .white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(required && empty ? HospitalTheme.rose : .clear, lineWidth: 1.5))
                .accessibilityLabel(title + (required ? ", obligatorio" : ""))
            if let hint { Text(hint).font(.caption).foregroundStyle(HospitalTheme.secondary) }
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
        ["open": "En consulta", "closed": "Finalizada", "draft": "Borrador", "ordered": "Emitida",
         "in_progress": "En consulta", "checked_in": "Registrado en recepción", "confirmed": "Programada",
         "scheduled": "Programada", "completed": "Finalizada", "cancelled": "Cancelada",
         "pending": "Pendiente", "pendiente": "Pendiente", "en_proceso": "En proceso", "completado": "Completado", "entregada": "Entregada", "anulada": "Anulada", "no_show": "No atendida"][value] ?? "Estado no disponible"
    }

}
