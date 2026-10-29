import SwiftUI

@MainActor
struct MobileModuleView: View {
    @ObservedObject var model: MobileModuleViewModel
    let module: String
    let role: String
    let search: String
    let period: (String) -> String
    let navigate: (String) -> Void
    @Environment(\.openURL) private var openURL
    @State private var cancelling: MobileItem?
    @State private var cancellationReason = ""
    @State private var password = ""
    @State private var repeatedPassword = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.loading || model.saving { ProgressView(model.saving ? "Guardando…" : "Cargando…") }
            if let error = model.error {
                Text(error).font(.footnote).foregroundStyle(.red)
                Button("Reintentar", systemImage: "arrow.clockwise") { Task { await model.load(module) } }
            }
            if let confirmation = model.confirmation { Text(confirmation).font(.footnote).foregroundStyle(HospitalTheme.wine) }
            if module == "request" { appointmentRequest }
            if module == "profile" { profileSettings }
            if ["appointments", "history", "laboratory", "prescriptions", "notifications"].contains(module) {
                Toggle("Filtrar por fecha y hora", isOn: $model.filterDates)
                if model.filterDates {
                    DatePicker("Desde", selection: $model.from)
                    DatePicker("Hasta", selection: $model.to)
                }
                Button("Buscar y actualizar", systemImage: "magnifyingglass") {
                    model.query = search; Task { await model.load(module) }
                }
            }
            ForEach(Array((model.page?.sections ?? []).enumerated()), id: \.offset) { _, section in
                Text(section.title).font(.headline)
                HospitalCard {
                    if section.fields.isEmpty { Text("Sin registros.").font(.footnote).foregroundStyle(HospitalTheme.secondary) }
                    ForEach(Array(section.fields.enumerated()), id: \.offset) { _, field in
                        if matches(field.label + " " + field.value) { fieldView(field) }
                    }
                }
            }
            if module == "request" { Text("Mis solicitudes").font(.headline) }
            ForEach(model.items.filter { matches($0.title + " " + ($0.subtitle ?? "") + " " + $0.details.map(\.value).joined(separator: " ")) }) { item in
                HospitalCard {
                    Text(item.title).font(.subheadline.weight(.semibold))
                    if let subtitle = item.subtitle { Text(subtitle).font(.footnote).foregroundStyle(HospitalTheme.secondary) }
                    Text(DoctorDate.display(item.event_at)).font(.caption)
                    HospitalBadge(text: MobileFormatting.status(item.status), warning: ["pending", "draft", "unread"].contains(item.status))
                    DisclosureGroup("Ver detalle") {
                        ForEach(Array(item.details.enumerated()), id: \.offset) { _, field in fieldView(field) }
                    }.font(.footnote)
                    if item.action == "cancel_appointment" {
                        Button("Cancelar cita", systemImage: "calendar.badge.minus", role: .destructive) {
                            cancellationReason = ""; cancelling = item
                        }
                    }
                    if item.action == "mark_read" {
                        Button("Marcar como leída", systemImage: "checkmark") { Task { await model.markRead(item) } }
                    }
                    if let document = item.document_id {
                        Button("Abrir documento", systemImage: "doc.text") {
                            Task { if let url = await model.documentURL(document) { openURL(url) } }
                        }
                    }
                }
            }
            if model.items.isEmpty && model.page != nil && module != "profile" && !model.loading {
                HospitalCard { Text("No hay registros que coincidan con esta consulta.").font(.footnote).foregroundStyle(HospitalTheme.secondary) }
            }
            if model.page?.has_more == true {
                Button("Cargar más", systemImage: "chevron.down") { Task { await model.load(module, more: true) } }
            }
            if module == "appointments" { Button("Solicitar atención", systemImage: "calendar.badge.plus") { navigate("request") } }
        }
        .disabled(model.loading || model.saving)
        .alert("Cancelar cita", isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } })) {
            TextField("Motivo de cancelación", text: $cancellationReason)
            Button("Cancelar cita", role: .destructive) {
                if let item = cancelling { let reason = cancellationReason; Task { await model.cancel(item, reason: reason) } }
                cancelling = nil
            }.disabled(cancellationReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Conservar cita", role: .cancel) { cancelling = nil }
        }
        .onDisappear { password = ""; repeatedPassword = "" }
    }

    private var appointmentRequest: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Especialidad", selection: $model.specialty) {
                Text("Seleccionar especialidad").tag(nil as UUID?)
                ForEach((model.page?.options ?? []).filter { $0.kind == "specialty" }) { option in Text(option.name).tag(Optional(option.id)) }
            }
            if model.page?.options.isEmpty == true { Text("No hay especialidades disponibles en el catálogo.").font(.footnote) }
            TextField("Motivo de consulta", text: $model.reason, axis: .vertical).lineLimit(3...6).textFieldStyle(.roundedBorder)
            DatePicker("Fecha preferida", selection: $model.preferredDay, in: Date()..., displayedComponents: .date)
            DatePicker("Desde", selection: $model.preferredFrom, displayedComponents: .hourAndMinute)
            DatePicker("Hasta", selection: $model.preferredTo, displayedComponents: .hourAndMinute)
            Text("La disponibilidad se confirmará al programar.").font(.footnote).foregroundStyle(HospitalTheme.secondary)
            Button("Enviar solicitud", systemImage: "paperplane") { Task { await model.requestAppointment() } }
                .buttonStyle(.borderedProminent).disabled(!model.canRequest || model.page == nil)
        }
    }

    private var profileSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Contacto").font(.headline)
            TextField("Teléfono", text: $model.phone).keyboardType(.phonePad).textFieldStyle(.roundedBorder)
            Button("Guardar teléfono", systemImage: "checkmark") { Task { await model.savePhone() } }
            if role == "patient" {
                Text("Contacto de emergencia").font(.headline)
                TextField("Nombres", text: $model.emergencyGiven).textFieldStyle(.roundedBorder)
                TextField("Apellidos", text: $model.emergencyFamily).textFieldStyle(.roundedBorder)
                TextField("Teléfono de emergencia", text: $model.emergencyPhone).keyboardType(.phonePad).textFieldStyle(.roundedBorder)
                TextField("Parentesco", text: $model.relationship).textFieldStyle(.roundedBorder)
                Button("Guardar contacto", systemImage: "person.crop.circle.badge.checkmark") { Task { await model.saveEmergency() } }
            }
            Text("Preferencias de notificaciones").font(.headline)
            ForEach(model.page?.preferences ?? []) { preference in
                Toggle(preference.name, isOn: Binding(get: { preference.enabled }, set: { value in
                    Task { await model.setPreference(preference, enabled: value) }
                }))
            }
            DisclosureGroup("Cambiar contraseña") {
                SecureField("Nueva contraseña", text: $password).textContentType(.newPassword)
                SecureField("Repetir contraseña", text: $repeatedPassword).textContentType(.newPassword)
                Button("Actualizar contraseña", systemImage: "lock.rotation") {
                    let value = password; password = ""; repeatedPassword = ""
                    Task { await model.changePassword(value) }
                }.disabled(password.count < 12 || password != repeatedPassword)
            }
        }
    }

    private func matches(_ value: String) -> Bool { search.isEmpty || value.localizedCaseInsensitiveContains(search) }
    private func fieldView(_ field: MobileField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(field.label).font(.caption.weight(.semibold))
            Text(field.label == "Horario" ? period(field.value) : field.value).font(.footnote).foregroundStyle(HospitalTheme.secondary).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
    }
}

@MainActor
struct DoctorPrescriptionView: View {
    @ObservedObject var doctor: DoctorViewModel
    @ObservedObject var model: MobileModuleViewModel
    let search: String
    let period: (String) -> String
    let navigate: (String) -> Void
    @State private var medication: UUID?
    @State private var unit: UUID?
    @State private var route: UUID?
    @State private var dose = ""
    @State private var interval = ""
    @State private var quantity = ""
    @State private var instructions = ""
    @State private var starts = Date()
    @State private var ends = Date()
    @State private var hasEnd = false
    @State private var confirmIssue = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Paciente / turno", selection: Binding(get: { doctor.selectedAppointmentID }, set: { value in
                doctor.select(value); model.prescriptionLines = []
            })) {
                Text("Seleccionar paciente").tag(nil as UUID?)
                ForEach(doctor.workspace?.appointments ?? []) { item in Text(item.patient_name).tag(Optional(item.id)) }
            }
            if doctor.loadingChart { ProgressView() }
            if let error = doctor.error { Text(error).font(.footnote).foregroundStyle(.red) }
            if doctor.canEditConsultation {
                if let chart = doctor.contextChart {
                    Text("Alergias registradas: " + (chart.allergies.isEmpty ? "Sin registros" : chart.allergies.joined(separator: ", ")))
                        .font(.footnote).foregroundStyle(HospitalTheme.wine)
                }
                optionPicker("Medicamento", kind: "medication", selection: $medication)
                if let page = model.page, !page.options.contains(where: { $0.kind == "medication" }) {
                    Text("No hay medicamentos activos en el catálogo de la sede.").font(.footnote).foregroundStyle(HospitalTheme.secondary)
                }
                HStack { TextField("Dosis", text: $dose); TextField("Cada cuántas horas", text: $interval) }.keyboardType(.decimalPad)
                optionPicker("Unidad de dosis", kind: "unit", selection: $unit)
                optionPicker("Vía", kind: "route", selection: $route)
                TextField("Cantidad a dispensar", text: $quantity).keyboardType(.decimalPad)
                TextField("Indicaciones", text: $instructions, axis: .vertical).lineLimit(2...5)
                DatePicker("Inicio", selection: $starts, displayedComponents: .date)
                Toggle("Fecha de finalización", isOn: $hasEnd)
                if hasEnd { DatePicker("Fin", selection: $ends, in: starts..., displayedComponents: .date) }
                Button("Añadir medicamento", systemImage: "plus") { addLine() }.disabled(!validLine || model.prescriptionLines.count >= 30)
                ForEach(model.prescriptionLines) { line in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(model.page?.options.first { $0.id == line.medication_id }?.name ?? "Medicamento").font(.subheadline)
                            Text("\(NSDecimalNumber(decimal: line.dose).stringValue) · cada \(NSDecimalNumber(decimal: line.interval_hours).stringValue) horas").font(.caption)
                        }
                        Spacer()
                        Button { model.prescriptionLines.removeAll { $0.id == line.id } } label: { Image(systemName: "trash") }.accessibilityLabel("Quitar medicamento")
                    }
                }
                Button("Emitir receta", systemImage: "signature") { confirmIssue = true }
                    .buttonStyle(.borderedProminent).disabled(model.prescriptionLines.isEmpty)
            } else {
                Text("Selecciona una consulta abierta para emitir la receta.").font(.footnote)
                Button("Ir a consulta", systemImage: "cross.case") { navigate("consultation") }
            }
            Text("Mis recetas").font(.headline)
            MobileModuleView(model: model, module: "prescriptions", role: "doctor", search: search, period: period, navigate: navigate)
        }
        .textFieldStyle(.roundedBorder)
        .disabled(model.saving || model.loading || doctor.loadingChart)
        .task(id: doctor.selectedAppointmentID) {
            model.alignPrescription(appointment: doctor.selectedAppointmentID)
            await doctor.loadChart()
        }
        .onChange(of: doctor.selectedAppointmentID) { _, _ in
            medication = nil; unit = nil; route = nil; dose = ""; interval = ""; quantity = ""; instructions = ""
            starts = Date(); ends = starts; hasEnd = false
        }
        .onChange(of: starts) { _, value in if ends < value { ends = value } }
        .confirmationDialog("¿Emitir y firmar esta receta?", isPresented: $confirmIssue, titleVisibility: .visible) {
            Button("Emitir receta") { if let encounter = doctor.activeConsultation { Task { await model.issuePrescription(encounter: encounter.id) } } }
            Button("Cancelar", role: .cancel) { }
        }
    }

    private func decimal(_ value: String) -> Decimal? {
        guard value.range(of: "^[0-9]+([.,][0-9]{1,4})?$", options: .regularExpression) != nil,
              let number = Decimal(string: value.replacingOccurrences(of: ",", with: ".")), number > 0 else { return nil }
        return number
    }
    private var validLine: Bool {
        medication != nil && unit != nil && route != nil && decimal(dose) != nil && decimal(interval) != nil
            && decimal(quantity) != nil && !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && instructions.count <= 2000 && (!hasEnd || ends >= starts)
    }
    private func addLine() {
        guard validLine, let medication, let unit, let route, let dose = decimal(dose),
              let interval = decimal(interval), let quantity = decimal(quantity) else { return }
        model.prescriptionLines.append(PrescriptionLine(medication_id: medication, dose: dose, dose_unit_id: unit,
            route_id: route, interval_hours: interval, instructions: instructions,
            starts_on: MobileFormatting.day(starts), ends_on: hasEnd ? MobileFormatting.day(ends) : nil, quantity: quantity))
        self.medication = nil; self.dose = ""; self.interval = ""; self.quantity = ""; instructions = ""
    }
    private func optionPicker(_ title: String, kind: String, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            Text("Seleccionar").tag(nil as UUID?)
            ForEach((model.page?.options ?? []).filter { $0.kind == kind }) { item in Text(item.name).tag(Optional(item.id)) }
        }.pickerStyle(.menu)
    }
}
