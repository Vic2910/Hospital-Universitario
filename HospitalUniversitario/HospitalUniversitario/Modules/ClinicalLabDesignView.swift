import SwiftUI

struct ClinicalLabDesignView: View {
    @ObservedObject var model: ClinicalLabDesignStore
    let role: String
    let screenID: String
    let navigate: (String) -> Void
    @State private var query = ""
    @State private var patientDate = Date()
    @State private var filterPatientDate = false
    @State private var category = "Todos"
    @State private var filterDate = false
    @State private var date = Date()
    @State private var modal: String?
    @State private var entryKind = "Observación"
    @State private var entryText = ""
    @State private var medication = ""
    @State private var rxDose = ""
    @State private var rxUnit = ""
    @State private var rxFrequency = ""
    @State private var rxRoute = ""
    @State private var rxDuration = ""
    @State private var rxQuantity = ""
    private var prescription: ClinicalPrescriptionDetails { .init(dose: rxDose, doseUnit: rxUnit, frequencyHours: rxFrequency, route: rxRoute, durationDays: rxDuration, quantity: rxQuantity) }
    @State private var selectedLabID: UUID?
    @State private var labReturnModal = "record"
    private var selectedLab: ClinicalLabRequest? { model.requests.first { $0.id == selectedLabID && $0.patient.id == patient?.id } }
    @State private var linkedRequest: UUID?
    private var patient: ClinicalLabPatient? { model.patient(for: role) }
    private var labs: [ClinicalLabRequest] {
        model.requests.filter { $0.patient.id == patient?.id && (modal == "record" || modal == "lab-detail" || ((category == "Todos" || $0.exam.category.rawValue == category)
            && (!filterDate || Calendar.current.isDate($0.requestedAt, inSameDayAs: date)))) }.sorted { $0.requestedAt > $1.requestedAt }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let modal, let patient {
                VStack(spacing: 22) {
                    HStack {
                        Button("Volver") { closeModal() }.font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(modal == "request" ? "PASO 2 DE 2" : "FICHA CLÍNICA").font(.caption.weight(.semibold)).foregroundStyle(HospitalTheme.secondary)
                    }
                    if modal != "lab-detail" {
                    Image(systemName: modal == "lab-detail" && selectedLab?.state != .completed ? "clock" : "checkmark").font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 82, height: 82).background(HospitalTheme.wine, in: Circle()).accessibilityHidden(true)
                    }
                    Text(modal == "lab-detail" ? "Detalle de examen" : modal == "request" ? "Solicitar exámenes" : modal == "entry" ? entryKind : modal == "results" ? (role == "patient" ? "Mis laboratorios" : "Solicitudes y resultados") : (role == "patient" ? "Mi expediente" : "Expediente completo"))
                        .font(.system(size: 27, weight: .bold)).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                    if modal != "lab-detail" {
                    Text(patient.fullName).font(.headline).foregroundStyle(HospitalTheme.secondary)
                    VStack(spacing: 8) {
                        Text(modal == "lab-detail" ? (selectedLab?.requestedAt.formatted(date: .abbreviated, time: .shortened) ?? "No hay datos reales") : modal == "request" ? model.requestDate.formatted(date: .abbreviated, time: .shortened) : patient.record).font(.headline)
                        Text(modal == "lab-detail" ? (selectedLab?.exam.name ?? "No hay datos reales") : modal == "request" ? model.doctorName : "DUI: \(patient.dui)").font(.subheadline)
                    }.frame(maxWidth: .infinity).padding(18).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 16))
                    }
                    Text("Datos locales de ejemplo · Sin envío al hospital").font(.caption).foregroundStyle(HospitalTheme.secondary)
                    if modal == "request" { requestForm(patient) }
                    else if modal == "entry" { entryForm }
                    else if modal == "lab-detail" { labDetail }
                    else if modal == "results" { laboratorySection }
                    else { recordBody(patient) }
                }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(HospitalTheme.rose, lineWidth: 1))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(screenID == "patients" ? "TU PRÁCTICA MÉDICA" : screenID == "laboratory" ? "ATENCIÓN CLÍNICA" : "HISTORIA DEL PACIENTE").font(.caption.weight(.bold)).tracking(1)
                    Text(screenID == "patients" ? "Tus pacientes, su evolución" : screenID == "laboratory" ? "Laboratorio, paso a paso" : "Un expediente, toda la información").font(.system(size: 24, weight: .bold))
                    Text(screenID == "patients" ? "Busca por fecha, DUI o nombre. Abre una ficha para revisar su evolución clínica." : screenID == "laboratory" ? "1. Busca al paciente. 2. Prepara su solicitud." : "Busca al paciente para abrir su ficha completa.").font(.footnote)
                }.foregroundStyle(.white).padding(22).frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient.vinoDestacado, in: RoundedRectangle(cornerRadius: 22))
                Text("Prototipo local · Sin escritura en Supabase").font(.caption).foregroundStyle(HospitalTheme.secondary)
                if role == "doctor" { searchSection }
                if let patient, screenID != "patients" {
                    PatientFormCard(titulo: patient.fullName, icono: "person.text.rectangle") {
                        Text("DUI: \(patient.dui) · \(patient.record)").font(.footnote)
                        if screenID == "laboratory" && role == "doctor" {
                            Button("Solicitar exámenes") { model.begin(role: role); modal = "request" }.buttonStyle(HospitalPrimaryButtonStyle())
                        } else {
                            Button("Abrir expediente completo") { modal = "record" }.buttonStyle(HospitalPrimaryButtonStyle())
                        }
                        if screenID == "laboratory" && role != "doctor" { Button("Ver solicitudes y resultados") { modal = "results" }.buttonStyle(.bordered) }
                    }
                } else if screenID != "patients" { HospitalCard { Text("Selecciona un paciente para continuar.").font(.subheadline) } }
            }
            if let message = model.confirmation { Text(message).font(.footnote).foregroundStyle(HospitalTheme.wine).accessibilityLabel(message) }
        }.tint(HospitalTheme.wine)
        .onChange(of: screenID) { _, value in if ["patients", "laboratory"].contains(value) { closeModal() } }
    }
    private func closeModal() { if modal == "lab-detail" { modal = labReturnModal; selectedLabID = nil; return }; model.preparing = false; modal = nil; entryText = ""; medication = ""; linkedRequest = nil; rxDose = ""; rxUnit = ""; rxFrequency = ""; rxRoute = ""; rxDuration = ""; rxQuantity = "" }
    private var searchSection: some View {
        PatientFormCard(titulo: screenID == "patients" ? "Encuentra a tu paciente" : screenID == "laboratory" ? "Buscar paciente" : "Buscar expediente", icono: "magnifyingglass") {
            TextField("DUI o nombre del paciente", text: $query).textFieldStyle(.roundedBorder).accessibilityLabel("DUI o nombre del paciente")
            let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "-", with: "")
            if screenID == "patients" {
                HStack {
                    Button("Todos") { filterPatientDate = false }
                    Button("Hoy") { patientDate = Date(); filterPatientDate = true }
                    Button("Mañana") { patientDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())!; filterPatientDate = true }
                }.buttonStyle(.bordered).font(.caption)
                DatePicker("Fecha de atención", selection: $patientDate, displayedComponents: .date)
                    .onChange(of: patientDate) { _, _ in filterPatientDate = true }
                Text(filterPatientDate ? "Coincidencias por fecha de atención" : "Todos los pacientes del ejemplo").font(.caption).foregroundStyle(HospitalTheme.secondary)
            }
            let matches = model.patients.filter {
                (normalized.isEmpty || ($0.fullName + " " + $0.dui.replacingOccurrences(of: "-", with: "")).localizedStandardContains(normalized))
                && (screenID != "patients" || !filterPatientDate || model.ownVisits(patientID: $0.id).contains { Calendar.current.isDate($0.date, inSameDayAs: patientDate) })
            }
            if screenID == "patients" { Text("\(matches.count) coincidencias").font(.subheadline.weight(.semibold)) }
            ForEach(matches) { item in
                Button {
                    model.select(item.id); category = "Todos"; filterDate = false
                    if ["chart", "patients"].contains(screenID) { modal = "record" }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        if screenID == "patients" {
                            Text(item.fullName.split(separator: " ").prefix(2).compactMap(\.first).map { String($0) }.joined())
                                .font(.system(size: 13, weight: .bold)).frame(width: 44, height: 44)
                                .background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 15))
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.fullName).font(.system(size: 17, weight: .bold))
                            Text("DUI: \(item.dui) · \(item.age) años").font(.caption)
                            if screenID == "patients" {
                                Text("Teléfono: \(item.phone)").font(.caption).foregroundStyle(HospitalTheme.secondary)
                                let visits = model.ownVisits(patientID: item.id)
                                Text("\(visits.filter { $0.status != "Programada" }.count) consultas · \(model.requests.filter { $0.patient.id == item.id && $0.state != .completed }.count) estudios pendientes").font(.caption.weight(.semibold))
                                Text(visits.first.map { "Última / próxima atención: " + $0.date.formatted(date: .abbreviated, time: .omitted) } ?? "Sin atenciones registradas").font(.caption).foregroundStyle(HospitalTheme.secondary)
                                Text("Ver ficha e historial").font(.caption.weight(.bold))
                            }
                        }
                        Spacer(); Image(systemName: patient?.id == item.id ? "checkmark.circle.fill" : "chevron.right")
                    }.foregroundStyle(HospitalTheme.wine).padding(16).background(screenID == "patients" ? Color.white : HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(HospitalTheme.wine.opacity(0.14), lineWidth: 1))
                }.buttonStyle(.plain).accessibilityLabel("Seleccionar a \(item.fullName)")
            }
            if matches.isEmpty { Text("No hay pacientes que coincidan.").font(.footnote) }
        }
    }
    private func demographics(_ patient: ClinicalLabPatient) -> some View {
        ClinicalPatientIdentityView(givenName: patient.givenName, familyName: patient.familyName, fullName: patient.fullName, age: DoctorConsultationFields.age(patient.age), dui: patient.dui, email: patient.email, phone: patient.phone, record: patient.record)
    }
    private func recordBody(_ patient: ClinicalLabPatient) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            PatientFormCard(titulo: "Datos personales", icono: "person") { demographics(patient) }
            PatientFormCard(titulo: "Historial clínico de mis consultas", icono: "clock.arrow.circlepath") {
                Text("Solo tus consultas con este paciente. Las próximas citas no son antecedentes clínicos.").font(.caption).foregroundStyle(HospitalTheme.secondary)
                let visits = model.ownVisits(patientID: patient.id).filter { $0.status != "Programada" }
                if visits.isEmpty { Text("Sin consultas previas registradas.").font(.footnote) }
                ForEach(visits) { visit in
                    HospitalCard {
                        Label(visit.date.formatted(date: .abbreviated, time: .shortened), systemImage: "clock").font(.caption.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
                        Text(visit.reason).font(.subheadline.weight(.semibold))
                        Text(visit.plan).font(.footnote).foregroundStyle(HospitalTheme.secondary)
                        Text(visit.status).font(.caption)
                    }.overlay(RoundedRectangle(cornerRadius: 14).stroke(HospitalTheme.rose, lineWidth: 1))
                }
            }
            PatientFormCard(titulo: "Historial y signos vitales", icono: "heart.text.square") {
                let last = model.requests.filter { $0.patient.id == patient.id && $0.weightKg != nil }.sorted { $0.requestedAt > $1.requestedAt }.first
                DoctorConsultationField(label: "Peso", value: last?.weightKg.map { "\($0) kg" } ?? "No hay datos reales")
                DoctorConsultationField(label: "Altura", value: last?.heightCm.map { "\($0) cm" } ?? "No hay datos reales")
                DoctorConsultationField(label: "Otros signos vitales y antecedentes", value: "Sin registros en este prototipo; no se inventan antecedentes.")
                if let last { Text("Registrado por \(last.doctorName) · \(last.requestedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption) }
            }
            PatientFormCard(titulo: "Notas y recetas", icono: "doc.text") {
                let entries = model.entries.filter { $0.patientID == patient.id }
                if entries.isEmpty { Text("Sin notas ni recetas registradas.").font(.footnote) }
                ForEach(entries) { entry in
                    HospitalCard {
                        Text(entry.kind == "Receta" ? "Receta local · No emitida" : "Observación").font(.subheadline.weight(.semibold))
                        if let medication = entry.medication { Text(medication).font(.subheadline.weight(.semibold)) }
                        if let rx = entry.prescription {
                            DoctorConsultationField(label: "Dosis", value: rx.dose + " " + rx.doseUnit)
                            DoctorConsultationField(label: "Cada", value: rx.frequencyHours + " horas")
                            DoctorConsultationField(label: "Vía", value: rx.route)
                            DoctorConsultationField(label: "Durante", value: rx.durationDays + " días")
                            DoctorConsultationField(label: "Cantidad", value: rx.quantity)
                        }
                        DoctorConsultationField(label: entry.kind == "Receta" ? "Observaciones" : "Nota", value: entry.text)
                        Text("\(entry.authorName) · \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                    }
                }
                if role == "doctor" { entryButtons(request: nil) }
            }
            laboratorySection
        }
    }
    private func requestForm(_ patient: ClinicalLabPatient) -> some View {
        PatientFormCard(titulo: "Examen y valoración clínica", icono: "testtube.2") {
            HStack(alignment: .top, spacing: 12) {
                DoctorConsultationField(label: "Clínica", value: model.clinicName)
                DoctorConsultationField(label: "Turno de consulta", value: patient.consultationTurn)
            }
            Text("01 · Examen y motivo").font(.caption.weight(.bold)).foregroundStyle(HospitalTheme.wine)
            Picker("Tipo de examen", selection: $model.examID) { Text("Seleccionar examen").tag(""); ForEach(ClinicalLabExam.basic) { Text($0.name).tag($0.id) } }
            TextField("Motivo del examen", text: $model.observation, axis: .vertical).lineLimit(3...6).textFieldStyle(.roundedBorder)
            Divider()
            Text("02 · Valoración clínica").font(.caption.weight(.bold)).foregroundStyle(HospitalTheme.wine)
            HStack(spacing: 12) {
                VStack(alignment: .leading) { Text("Peso (kg)").font(.caption); TextField("Peso (kg)", text: $model.weight).keyboardType(.decimalPad).textFieldStyle(.roundedBorder) }
                VStack(alignment: .leading) { Text("Altura (cm)").font(.caption); TextField("Altura (cm)", text: $model.height).keyboardType(.decimalPad).textFieldStyle(.roundedBorder) }
            }
            Text("Campos obligatorios. Peso: 0,1–500 kg. Altura: 20–250 cm. Hasta dos decimales; se admite coma o punto.").font(.caption).foregroundStyle(HospitalTheme.secondary)
            Button("Solicitar") { model.submit(role: role); category = "Todos"; filterDate = false; closeModal() }
                .buttonStyle(ClinicalTicketPrimaryStyle()).disabled(!model.canSubmit(role: role))
            Button("Cancelar", action: closeModal).buttonStyle(.bordered)
        }
    }
    private func entryButtons(request: UUID?) -> some View {
        HStack {
            Button("Añadir observación") { linkedRequest = request; entryKind = "Observación"; entryText = ""; medication = ""; modal = "entry" }
            Button("Añadir receta") { linkedRequest = request; entryKind = "Receta"; entryText = ""; medication = ""; modal = "entry" }
        }.font(.footnote).buttonStyle(.bordered)
    }
    private var entryForm: some View {
        PatientFormCard(titulo: entryKind, icono: "square.and.pencil") {
            Text("\(patient?.fullName ?? "") · \(model.doctorName)").font(.subheadline)
            if entryKind == "Receta" {
                Text("Borrador local. No emite una receta clínica.").font(.footnote)
                TextField("Medicamento", text: $medication).textFieldStyle(.roundedBorder)
                TextField("Dosis", text: $rxDose).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                TextField("Unidad de dosis", text: $rxUnit).textFieldStyle(.roundedBorder)
                TextField("Cada cuántas horas", text: $rxFrequency).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                TextField("Vía", text: $rxRoute).textFieldStyle(.roundedBorder)
                TextField("Durante (días)", text: $rxDuration).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                TextField("Cantidad a dispensar", text: $rxQuantity).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
            }
            TextField(entryKind == "Receta" ? "Observaciones" : "Observación", text: $entryText, axis: .vertical).lineLimit(3...6).textFieldStyle(.roundedBorder)
            Button("Guardar") {
                if model.addEntry(role: role, kind: entryKind, medication: medication, text: entryText, requestID: linkedRequest, prescription: entryKind == "Receta" ? prescription : nil) { closeModal() }
            }.buttonStyle(HospitalPrimaryButtonStyle()).disabled(entryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || entryText.count > 2000 || (entryKind == "Receta" && (medication.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !prescription.isValid)))
        }
    }
    private var laboratorySection: some View {
        PatientFormCard(titulo: "Laboratorios del expediente", icono: "testtube.2") {
            Text("Más recientes primero · Solicitudes y resultados del paciente").font(.caption).foregroundStyle(HospitalTheme.secondary)
            if modal != "record" {
                Picker("Tipo de laboratorio", selection: $category) { Text("Todos").tag("Todos"); ForEach(ClinicalLabCategory.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) } }
                Toggle("Filtrar laboratorios por fecha", isOn: $filterDate)
                if filterDate { DatePicker("Fecha de laboratorio", selection: $date, displayedComponents: .date) }
            }
            if labs.isEmpty { Label("Este paciente todavía no tiene exámenes registrados.", systemImage: "testtube.2").font(.footnote).foregroundStyle(HospitalTheme.secondary).padding(.vertical, 14) }
            ForEach(labs) { request in
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(spacing: 3) {
                            Text(request.requestedAt.formatted(.dateTime.day())).font(.title2.weight(.bold))
                            Text(request.requestedAt.formatted(.dateTime.month(.abbreviated))).font(.caption.weight(.semibold))
                        }.foregroundStyle(HospitalTheme.wine).frame(width: 55, height: 62).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 7) {
                            Text(request.exam.name).font(.subheadline.weight(.bold))
                            Text(request.requestedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(HospitalTheme.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    ClinicalLabStateBadge(state: request.state)
                    Text(request.state == .completed ? ((request.result?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || !request.resultValues.isEmpty) ? "Resultado disponible para revisión" : "Informe pendiente de publicación") : request.state == .processing ? "El laboratorio está procesando el examen" : "Solicitud pendiente de procesamiento").font(.footnote).foregroundStyle(HospitalTheme.secondary)
                    Button { selectedLabID = request.id; labReturnModal = modal ?? "record"; modal = "lab-detail" } label: { HStack { Text("Ver detalle"); Spacer(); Image(systemName: "arrow.up.right") } }.font(.subheadline.weight(.semibold)).tint(HospitalTheme.wine)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(HospitalTheme.rose, lineWidth: 1))
                    .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 3).fill(HospitalTheme.wine).frame(width: 3).padding(.vertical, 20) }
            }
        }
    }
    @ViewBuilder private var labDetail: some View {
        if let request = selectedLab {
            VStack(alignment: .leading, spacing: 18) {
                PatientFormCard(titulo: "Paciente", icono: "person.crop.circle") {
                    HStack(spacing: 14) {
                        Text([request.patient.givenName, request.patient.familyName].compactMap { $0.first.map(String.init) }.joined()).font(.title2.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 58, height: 58).background(HospitalTheme.wine, in: RoundedRectangle(cornerRadius: 18))
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Nombre completo").font(.caption.weight(.semibold)).foregroundStyle(HospitalTheme.secondary)
                            Text(request.patient.fullName).font(.system(size: 18, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        DoctorConsultationField(label: "Edad", value: DoctorConsultationFields.age(request.patient.age))
                        DoctorConsultationField(label: "Teléfono", value: DoctorConsultationFields.value(request.patient.phone))
                    }.padding(14).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 14))
                }
                PatientFormCard(titulo: "Información del examen", icono: "testtube.2") {
                    Text(request.exam.name).font(.system(size: 21, weight: .bold))
                    ClinicalLabStateBadge(state: request.state)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Fecha de solicitud").font(.caption).foregroundStyle(HospitalTheme.secondary)
                        Text(request.requestedAt.formatted(date: .complete, time: .shortened)).font(.subheadline.weight(.semibold))
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 14))
                    DoctorConsultationField(label: "Tipo de examen", value: request.exam.category.rawValue)
                    HStack(alignment: .top) {
                        DoctorConsultationField(label: "Doctor solicitante", value: request.doctorName)
                        DoctorConsultationField(label: "Turno", value: request.consultationTurn)
                    }
                    DoctorConsultationField(label: "Clínica", value: request.clinicName)
                    Divider().overlay(HospitalTheme.rose)
                    DoctorConsultationField(label: "Motivo del examen", value: request.observation)
                }
                PatientFormCard(titulo: "Resultado del examen", icono: "doc.text.magnifyingglass") {
                    if request.state == .completed {
                        if let released = request.releasedAt { DoctorConsultationField(label: "Fecha de publicación", value: released.formatted(date: .abbreviated, time: .shortened)) }
                        ForEach(request.resultValues) { value in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(value.name).font(.subheadline.weight(.semibold))
                                Text("Valor obtenido").font(.caption).foregroundStyle(HospitalTheme.secondary)
                                Text(DoctorConsultationFields.value(value.value) + " " + value.unit).font(.system(size: 25, weight: .bold)).foregroundStyle(HospitalTheme.wine)
                                Divider().overlay(HospitalTheme.rose)
                                Text("Referencia: " + DoctorConsultationFields.value(value.reference)).font(.caption).foregroundStyle(HospitalTheme.secondary)
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 14))
                        }
                        DoctorConsultationField(label: "Observación del laboratorio", value: request.result ?? "No hay un informe publicado todavía")
                    } else {
                        Text(request.state == .processing ? "En Proceso" : "Pendiente").font(.title3.weight(.bold))
                        Text(request.state == .processing ? "El examen se está procesando. Los resultados aparecerán aquí cuando se publiquen." : "La solicitud está registrada y espera procesamiento. Todavía no hay resultados publicados.").font(.subheadline).foregroundStyle(HospitalTheme.secondary)
                    }
                }
                if role == "doctor" { entryButtons(request: request.id) }
                Button(labReturnModal == "record" ? "Volver al expediente" : "Volver a laboratorios", action: closeModal).buttonStyle(ClinicalTicketPrimaryStyle())
            }
        } else { Text("Este examen no está disponible para el paciente seleccionado.") }
    }

}

struct ClinicalLabStateBadge: View {
    let state: ClinicalLabState
    var body: some View {
        Label(state.rawValue, systemImage: state == .completed ? "checkmark.circle" : state == .processing ? "arrow.triangle.2.circlepath" : "clock")
            .font(.caption.weight(.semibold)).foregroundStyle(HospitalTheme.wine).padding(.horizontal, 10).padding(.vertical, 6)
            .background(state == .completed ? HospitalTheme.green : state == .processing ? Color(red: 231/255, green: 241/255, blue: 253/255) : Color(red: 1, green: 0.95, blue: 0.85), in: Capsule())
    }
}
private struct ClinicalLabDesignPreview: View {
    @StateObject private var model = ClinicalLabDesignStore()
    let role: String
    var body: some View { ScrollView { ClinicalLabDesignView(model: model, role: role, screenID: "laboratory", navigate: { _ in }).padding(17) }.background(HospitalTheme.background) }
}
#Preview("Laboratorios · solicitud independiente") { ClinicalLabDesignPreview(role: "doctor") }
#Preview("Laboratorios · Paciente") { ClinicalLabDesignPreview(role: "patient") }

private struct ClinicalTicketPrimaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 54)
            .background(Color(red: 33/255, green: 150/255, blue: 243/255), in: RoundedRectangle(cornerRadius: 12))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}
