import SwiftUI

/// Expedientes del médico: búsqueda (doctor_native_patients), expediente (doctor_native_chart) e historial de
/// consultas finalizadas con su detalle (recetas del chart y laboratorio de doctor_native_patient_labs).
/// La autorización la decide el servidor (private.treats_patient y e.doctor_id); la vista no filtra permisos.
@MainActor
struct DoctorRecordsView: View {
    @ObservedObject var model: DoctorViewModel
    let workspace: DoctorWorkspace
    let navigate: (String) -> Void
    @State private var showHistory = false
    @State private var historyLimit = DoctorRecordRules.historyPageSize
    @State private var detail: DoctorConsultation?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let patient = model.selectedPatient { record(patient) } else { searchScreen }
        }
        .task { model.adoptAppointmentPatient() }
        // Espera breve antes de consultar; escribir otra letra cancela la búsqueda pendiente.
        .task(id: model.patientQuery) { if model.selectedPatient == nil { await model.searchPatients() } }
        // Actualización segura del expediente abierto: misma selección o se descarta (DoctorViewModel.selectionGeneration).
        .task(id: model.selectedPatient?.id) {
            guard model.selectedPatient != nil else { return }
            await model.loadPatientLabs()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                await model.loadChart(silent: true)
            }
        }
        .onChange(of: model.selectedPatient?.id) { _, _ in showHistory = false; historyLimit = DoctorRecordRules.historyPageSize; detail = nil }
        .sheet(item: $detail) { consultation in consultationDetail(consultation).presentationDragIndicator(.visible) }
    }

    // MARK: Búsqueda

    private var searchScreen: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Label("EXPEDIENTES", systemImage: "folder.badge.person.crop").font(.caption.bold()).tracking(1.2)
                Text("Encuentra un expediente al instante").font(.title2.bold())
                Text("Busca por nombre, apellido, DUI, código de paciente o de expediente. Solo aparecen pacientes que tienes autorización para atender.")
                    .font(.subheadline).opacity(0.9).fixedSize(horizontal: false, vertical: true)
            }.foregroundStyle(.white).padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient.vinoDestacado, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.title3.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
                TextField("Nombre, apellido, DUI o código", text: $model.patientQuery)
                    .font(.body).textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                    .focused($searchFocused).accessibilityLabel("Buscar expediente")
                if model.directoryLoading { ProgressView().controlSize(.small) }
                else if !model.patientQuery.isEmpty {
                    Button { model.patientQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(HospitalTheme.secondary) }
                        .accessibilityLabel("Borrar búsqueda")
                }
            }
            .padding(.horizontal, 16).frame(minHeight: 58)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(searchFocused ? HospitalTheme.wine : HospitalTheme.rose, lineWidth: searchFocused ? 2 : 1.5))
            .shadow(color: HospitalTheme.ink.opacity(0.05), radius: 10, y: 4)

            if let page = model.directoryPage, model.directoryError == nil {
                Text(model.patientQuery.trimmingCharacters(in: .whitespaces).isEmpty
                     ? "Tus pacientes autorizados · \(page.total)"
                     : "\(page.total) \(page.total == 1 ? "resultado" : "resultados") para «\(model.patientQuery.trimmingCharacters(in: .whitespaces))»")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(HospitalTheme.secondary)
            }
            if let error = model.directoryError {
                HospitalNotice(text: error)
                Button("Reintentar búsqueda", systemImage: "arrow.clockwise") { Task { await model.loadPatients() } }.tint(HospitalTheme.wine)
            }
            if model.directoryLoading && model.patientDirectory.isEmpty {
                ProgressView("Buscando expedientes…").frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if model.patientDirectory.isEmpty && model.directoryPage != nil && model.directoryError == nil {
                emptyState(icon: "person.crop.circle.badge.questionmark", title: "Sin coincidencias",
                    text: model.patientQuery.isEmpty ? "Todavía no tienes pacientes asignados. Aparecerán aquí cuando recepción te asigne citas."
                        : "Ningún paciente autorizado coincide con la búsqueda. Revisa el nombre, el DUI o el código.")
            }
            LazyVStack(spacing: 12) {
                ForEach(model.patientDirectory) { patient in resultCard(patient) }
            }
            if model.directoryPage?.has_more == true {
                Button("Cargar más resultados") { Task { await model.loadPatients(more: true) } }
                    .frame(maxWidth: .infinity).disabled(model.directoryLoading).tint(HospitalTheme.wine)
            }
        }
    }

    /// Solo datos identificativos; ninguna información clínica en los resultados.
    private func resultCard(_ patient: DoctorAssignedPatient) -> some View {
        Button { searchFocused = false; model.openPatient(patient) } label: {
            HStack(alignment: .center, spacing: 14) {
                Text(patient.initials).font(.headline.bold()).foregroundStyle(HospitalTheme.wine)
                    .frame(width: 52, height: 52).background(HospitalTheme.rose, in: Circle())
                VStack(alignment: .leading, spacing: 7) {
                    Text(patient.full_name).font(.headline).foregroundStyle(HospitalTheme.ink).multilineTextAlignment(.leading)
                    ConsultationFlowLayout(spacing: 6) {
                        if let code = DoctorRecordRules.text(patient.patient_code) { chip("number", "Código \(code)") }
                        if let record = DoctorRecordRules.text(patient.record_number) { chip("folder", "Exp. \(record)") }
                        if let dui = DoctorRecordRules.text(patient.dui) { chip("person.text.rectangle", "DUI \(dui)") }
                        if let age = patient.age { chip("calendar", "\(age) años") }
                    }
                    HStack(spacing: 6) {
                        statusPill(patient.record_number == nil ? "Sin expediente vinculado" : "Expediente activo",
                                   icon: patient.record_number == nil ? "exclamationmark.circle" : "checkmark.seal.fill", positive: patient.record_number != nil)
                        if patient.active_encounter_id != nil { statusPill("En consulta", icon: "stethoscope", positive: true) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.subheadline.bold()).foregroundStyle(HospitalTheme.wine)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(HospitalTheme.rose, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Abrir expediente de \(patient.full_name)")
    }

    // MARK: Expediente

    @ViewBuilder
    private func record(_ patient: DoctorAssignedPatient) -> some View {
        let chart = model.chart?.patient.id == patient.id ? model.chart : nil
        Button { model.dismissPatient() } label: {
            Label("Volver a la búsqueda", systemImage: "chevron.left").font(.subheadline.weight(.semibold))
        }.tint(HospitalTheme.wine)
        header(patient, chart: chart)
        if chart == nil && model.loadingChart {
            ProgressView("Cargando expediente…").frame(maxWidth: .infinity).padding(.vertical, 20)
        } else if let chart {
            clinicalSummary(chart)
            actions(patient)
            historyButton(chart)
            if showHistory { history(chart) }
        } else if model.error == nil {
            emptyState(icon: "folder.badge.questionmark", title: "Expediente no disponible",
                text: "No se pudo cargar el expediente. Comprueba la conexión e inténtalo de nuevo.")
            Button("Reintentar", systemImage: "arrow.clockwise") { Task { await model.loadChart() } }.tint(HospitalTheme.wine)
        }
    }

    /// Cabecera única: los datos de identificación no se repiten en otras secciones.
    private func header(_ patient: DoctorAssignedPatient, chart: DoctorPatientChart?) -> some View {
        let code = DoctorRecordRules.text(chart?.patient.patient_code ?? patient.patient_code)
        let record = DoctorRecordRules.text(chart?.patient.record_number ?? patient.record_number)
        let birth = DoctorRecordRules.text(chart?.patient.birth_date ?? patient.birth_date)
        let rows: [(String, String, String?)] = [
            ("calendar", "Fecha de nacimiento", birth.map(Self.birthDate)),
            ("person.text.rectangle", "DUI", DoctorRecordRules.text(chart?.patient.identification ?? patient.dui)),
            ("phone", "Teléfono", DoctorRecordRules.text(chart?.patient.phone ?? patient.phone)),
            ("envelope", "Correo", DoctorRecordRules.text(chart?.patient.email ?? patient.email)),
            ("mappin.and.ellipse", "Ciudad", DoctorRecordRules.text(chart?.patient.address))]
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Text(patient.initials).font(.title.bold()).foregroundStyle(HospitalTheme.wine)
                    .frame(width: 72, height: 72).background(.white, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 4).padding(-4)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("EXPEDIENTE CLÍNICO").font(.caption2.weight(.heavy)).tracking(1.2).opacity(0.8)
                    Text(chart?.patient.full_name ?? patient.full_name).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            ConsultationFlowLayout(spacing: 8) {
                if let code { headerPill("number", "Código \(code)") }
                headerPill("folder", record.map { "Expediente \($0)" } ?? "Sin expediente")
                if let age = patient.age { headerPill("person", "\(age) años") }
                if patient.active_encounter_id != nil { headerPill("stethoscope", "En consulta") }
            }
            let visible = rows.compactMap { row in row.2.map { (row.0, row.1, $0) } }
            if !visible.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10, alignment: .topLeading)], alignment: .leading, spacing: 10) {
                    ForEach(Array(visible.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: row.0).font(.footnote.weight(.semibold)).frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.1).font(.caption2).opacity(0.8)
                                Text(row.2).font(.footnote.weight(.semibold)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            }
                            Spacer(minLength: 0)
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .foregroundStyle(.white).padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.vinoDestacado, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: HospitalTheme.wine.opacity(0.18), radius: 14, y: 6)
    }

    /// Antecedentes del expediente sin repetir alergias ni condiciones dentro de "Otros antecedentes".
    private func clinicalSummary(_ chart: DoctorPatientChart) -> some View {
        let grouped = Set(["alergia", "alergias", "condicion", "enfermedad"])
        let others = (chart.medical_history ?? []).filter { entry in
            let type = entry.split(separator: ":", maxSplits: 1).first.map { String($0).trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
            return !grouped.contains(type)
        }
        let groups: [(String, String, [String])] = [
            ("allergens", "Alergias", chart.allergies),
            ("heart.text.square", "Condiciones", chart.conditions),
            ("list.bullet.clipboard", "Otros antecedentes", others),
            ("pills", "Medicamentos registrados", chart.medications ?? [])].filter { !$0.2.isEmpty }
        return VStack(alignment: .leading, spacing: 14) {
            ConsultationBlockHeader(icon: "cross.case", title: "Información clínica", subtitle: "Antecedentes registrados en el expediente")
            if let blood = DoctorRecordRules.text(chart.blood_type) { summaryRow("drop.fill", "Grupo sanguíneo", [blood]) }
            if groups.isEmpty && DoctorRecordRules.text(chart.blood_type) == nil {
                Text("Sin antecedentes clínicos registrados.").font(.subheadline).foregroundStyle(HospitalTheme.secondary)
            }
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in summaryRow(group.0, group.1, group.2) }
        }.modifier(ConsultationCardStyle())
    }

    private func actions(_ patient: DoctorAssignedPatient) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { actionButtons(patient) }
            VStack(spacing: 10) { actionButtons(patient) }
        }
    }
    @ViewBuilder private func actionButtons(_ patient: DoctorAssignedPatient) -> some View {
        if patient.active_encounter_id != nil {
            actionButton("stethoscope", "Continuar consulta") { navigate("consultation") }
        }
        actionButton("testtube.2", "Laboratorios") { navigate("laboratory") }
        actionButton("bed.double", "Solicitar ingreso") { model.admissionForm = true; navigate("admissions") }
    }

    private func historyButton(_ chart: DoctorPatientChart) -> some View {
        let count = DoctorRecordRules.finishedHistory(chart.history).count
        return Button { withAnimation(.easeInOut(duration: 0.2)) { showHistory.toggle() } } label: {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath").font(.title3.weight(.semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(showHistory ? "OCULTAR HISTORIAL MÉDICO" : "VER HISTORIAL MÉDICO").font(.headline)
                    Text(count == 0 ? "Sin consultas finalizadas" : "\(count) \(count == 1 ? "consulta finalizada" : "consultas finalizadas")").font(.caption).opacity(0.9)
                }
                Spacer()
                Image(systemName: showHistory ? "chevron.up" : "chevron.down").font(.subheadline.bold())
            }
            .foregroundStyle(.white).padding(.horizontal, 18).frame(maxWidth: .infinity, minHeight: 64)
            .background(LinearGradient.vinoDestacado, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Muestra las consultas finalizadas, de la más reciente a la más antigua")
    }

    // MARK: Historial

    @ViewBuilder
    private func history(_ chart: DoctorPatientChart) -> some View {
        let entries = DoctorRecordRules.finishedHistory(chart.history)
        VStack(alignment: .leading, spacing: 14) {
            ConsultationBlockHeader(icon: "list.bullet.rectangle", title: "Historial médico",
                subtitle: "Consultas finalizadas que atendiste, de la más reciente a la más antigua")
            if entries.isEmpty {
                emptyState(icon: "doc.text.magnifyingglass", title: "Todavía no hay historial",
                    text: "Este paciente aún no tiene consultas finalizadas contigo. Las consultas abiertas no aparecen aquí.")
            }
            ForEach(Array(entries.prefix(historyLimit).enumerated()), id: \.element.id) { index, entry in
                timelineCard(entry, last: index == min(entries.count, historyLimit) - 1)
            }
            if entries.count > historyLimit {
                Button("Mostrar consultas anteriores (\(entries.count - historyLimit))") { historyLimit += DoctorRecordRules.historyPageSize }
                    .frame(maxWidth: .infinity).tint(HospitalTheme.wine)
            }
        }.modifier(ConsultationCardStyle())
    }

    private func timelineCard(_ entry: DoctorConsultation, last: Bool) -> some View {
        let date = DoctorDate.parse(entry.started_at)
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle().fill(HospitalTheme.wine).frame(width: 12, height: 12).overlay(Circle().stroke(HospitalTheme.rose, lineWidth: 3))
                if !last { Rectangle().fill(HospitalTheme.rose).frame(width: 2).frame(maxHeight: .infinity) }
            }.padding(.top, 6).accessibilityHidden(true)
            Button { detail = entry } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(ConsultationFormat.date(date)).font(.subheadline.bold()).foregroundStyle(HospitalTheme.ink)
                        Spacer(minLength: 8)
                        Text(ConsultationFormat.time(date)).font(.caption.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
                    }
                    HStack(spacing: 6) {
                        Label(DoctorRecordRules.text(entry.doctor_name) ?? (workspace.doctor_name.isEmpty ? "Médico responsable" : workspace.doctor_name), systemImage: "stethoscope")
                        if let specialty = DoctorRecordRules.text(entry.specialty) { Text("· \(specialty)") }
                    }.font(.caption).foregroundStyle(HospitalTheme.secondary)
                    if let reason = DoctorRecordRules.text(entry.reason) { line("Motivo", reason) }
                    if let diagnosis = DoctorRecordRules.text(entry.assessment) { line("Diagnóstico", diagnosis) }
                    if let observations = DoctorRecordRules.text(entry.objective) { line("Observaciones", observations) }
                    if let plan = DoctorRecordRules.text(entry.plan) { line("Tratamiento", plan) }
                    HStack { Spacer(); Label("Ver detalle", systemImage: "chevron.right").font(.caption.bold()).foregroundStyle(HospitalTheme.wine).labelStyle(.titleAndIcon) }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Consulta del \(ConsultationFormat.date(date)) a las \(ConsultationFormat.time(date))")
            .padding(.bottom, last ? 0 : 6)
        }
    }

    // MARK: Detalle de consulta

    private func consultationDetail(_ entry: DoctorConsultation) -> some View {
        let date = DoctorDate.parse(entry.started_at)
        let vitals = DoctorClinicalRules.recordedVitals.compactMap { vital in
            DoctorRecordRules.text(entry.vitals?[vital.key]).map { (vital, $0) }
        }
        let prescriptions = DoctorRecordRules.prescriptions(model.chart, encounter: entry.id)
        let unlinkedPrescriptions = !(model.chart?.prescriptions ?? []).isEmpty && (model.chart?.prescriptions ?? []).allSatisfy { $0.encounter_id == nil }
        let labs = DoctorRecordRules.labs(model.patientLabs, encounter: entry.id)
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ConsultationFormat.date(date)).font(.title3.bold())
                        Label(ConsultationFormat.time(date), systemImage: "clock")
                        Label(DoctorRecordRules.text(entry.doctor_name) ?? (workspace.doctor_name.isEmpty ? "Médico responsable" : workspace.doctor_name), systemImage: "stethoscope")
                        if let specialty = DoctorRecordRules.text(entry.specialty) { Label(specialty, systemImage: "cross.case") }
                        if let reason = DoctorRecordRules.text(entry.reason) { Label("Motivo: \(reason)", systemImage: "text.bubble") }
                    }.font(.subheadline).foregroundStyle(.white).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient.vinoDestacado, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    if !vitals.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            ConsultationBlockHeader(icon: "figure.stand", title: "Datos físicos", subtitle: "Medidas registradas en la consulta")
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                                ForEach(Array(vitals.enumerated()), id: \.offset) { _, item in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.0.label).font(.caption).foregroundStyle(HospitalTheme.secondary)
                                        Text("\(item.1) \(item.0.unit)").font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(HospitalTheme.ink)
                                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                            if let bmi = DoctorClinicalRules.bmi(entry.vitals ?? [:]) {
                                Text("IMC calculado: \(bmi) kg/m²").font(.footnote.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
                            }
                        }.modifier(ConsultationCardStyle())
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        ConsultationBlockHeader(icon: "stethoscope", title: "Evaluación médica", subtitle: "Información guardada al finalizar")
                        if let value = DoctorRecordRules.text(entry.subjective) { section("Síntomas", value) }
                        if let value = DoctorRecordRules.text(entry.assessment) { section("Diagnóstico", value + (DoctorRecordRules.text(entry.diagnosis_code).map { "\nCódigo: \($0)" } ?? "")) }
                        if let value = DoctorRecordRules.text(entry.objective) { section("Observaciones", value) }
                        if let value = DoctorRecordRules.text(entry.plan) { section("Tratamiento", value) }
                    }.modifier(ConsultationCardStyle())

                    VStack(alignment: .leading, spacing: 12) {
                        ConsultationBlockHeader(icon: "pills.fill", title: "Recetas", subtitle: "Emitidas en esta consulta")
                        if prescriptions.isEmpty {
                            Text(unlinkedPrescriptions ? "El servidor todavía no indica a qué consulta pertenece cada receta. Puedes verlas en Recetas." : "No se emitieron recetas en esta consulta.")
                                .font(.footnote).foregroundStyle(HospitalTheme.secondary)
                        }
                        ForEach(prescriptions) { prescription in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(prescription.code).font(.subheadline.bold()); Spacer(); Text(prescription.status == "pendiente" ? "Pendiente de entrega" : prescription.status.capitalized).font(.caption.bold()).foregroundStyle(HospitalTheme.wine) }
                                ForEach(Array(prescription.lines.enumerated()), id: \.offset) { _, line in Label(line, systemImage: "pills").font(.footnote) }
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }.modifier(ConsultationCardStyle())

                    VStack(alignment: .leading, spacing: 12) {
                        ConsultationBlockHeader(icon: "testtube.2", title: "Exámenes", subtitle: "Solicitados en esta consulta")
                        if model.patientLabsLoading && labs.isEmpty { ProgressView() }
                        else if labs.isEmpty { Text("No se solicitaron exámenes en esta consulta.").font(.footnote).foregroundStyle(HospitalTheme.secondary) }
                        ForEach(labs) { lab in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(lab.test_name).font(.subheadline.bold()); Spacer(); Text(DoctorRecordRules.publishedResult(lab) ? "Resultado publicado" : lab.status.capitalized).font(.caption.bold()).foregroundStyle(HospitalTheme.wine) }
                                if DoctorRecordRules.publishedResult(lab) {
                                    if let summary = DoctorRecordRules.text(lab.result_summary) { Text(summary).font(.footnote) }
                                    ForEach(Array((lab.parameters ?? []).enumerated()), id: \.offset) { _, parameter in
                                        if let value = DoctorRecordRules.text(parameter.value) {
                                            Text("\(parameter.label): \(value)\(parameter.unit.map { " \($0)" } ?? "")").font(.caption).foregroundStyle(HospitalTheme.ink)
                                        }
                                    }
                                }
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }.modifier(ConsultationCardStyle())
                }.padding(18)
            }
            .background(HospitalTheme.background)
            .navigationTitle("Detalle de consulta").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { detail = nil } } }
        }.tint(HospitalTheme.wine)
    }

    // MARK: Piezas

    private func chip(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
            .padding(.horizontal, 9).padding(.vertical, 4).background(HospitalTheme.rose, in: Capsule())
    }
    private func headerPill(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon).font(.caption.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 7).background(Color.white.opacity(0.16), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
    }
    private func statusPill(_ text: String, icon: String, positive: Bool) -> some View {
        Label(text, systemImage: icon).font(.caption2.bold())
            .foregroundStyle(positive ? Color(red: 0.13, green: 0.5, blue: 0.3) : Color(red: 0.6, green: 0.4, blue: 0.0))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(positive ? HospitalTheme.green : Color(red: 1, green: 0.95, blue: 0.85), in: Capsule())
    }
    private func summaryRow(_ icon: String, _ title: String, _ values: [String]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
                .frame(width: 32, height: 32).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(HospitalTheme.secondary)
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Text(value).font(.subheadline).foregroundStyle(HospitalTheme.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
    private func actionButton(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 46)
        }.buttonStyle(.bordered).tint(HospitalTheme.wine)
    }
    private func line(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(HospitalTheme.secondary)
            Text(value).font(.footnote).foregroundStyle(HospitalTheme.ink).lineLimit(3)
        }
    }
    private func section(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(HospitalTheme.secondary)
            Text(value).font(.body).foregroundStyle(HospitalTheme.ink).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private func emptyState(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 34, weight: .semibold)).foregroundStyle(HospitalTheme.wine)
                .frame(width: 70, height: 70).background(HospitalTheme.rose, in: Circle())
            Text(title).font(.headline).foregroundStyle(HospitalTheme.ink)
            Text(text).font(.subheadline).foregroundStyle(HospitalTheme.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.padding(24).frame(maxWidth: .infinity)
            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    static func birthDate(_ value: String) -> String {
        let parser = DateFormatter(); parser.locale = Locale(identifier: "en_US_POSIX"); parser.timeZone = DoctorClinicalRules.timeZone
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: String(value.prefix(10))) else { return value }
        return date.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: Locale(identifier: "es_SV"), calendar: DoctorClinicalRules.calendar, timeZone: DoctorClinicalRules.timeZone))
    }
}
