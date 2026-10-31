import SwiftUI

/// Historial propio del médico dentro de Pacientes, separado del panel general.
struct DoctorPatientHistoryView: View {
    let patients: [DoctorDashboardPatient]
    let loadHistory: (UUID, Date?, Date?) async throws -> [DoctorConsultation]
    @State private var patientQuery = ""
    @State private var selected: UUID?
    @State private var filterDates = false
    @State private var from = Calendar.current.startOfDay(for: Date())
    @State private var to = Calendar.current.startOfDay(for: Date())
    @State private var history: [DoctorConsultation] = []
    @State private var loading = false
    @State private var error: String?
    @State private var searched = false
    @State private var request = UUID()

    private var matchingPatients: [DoctorDashboardPatient] {
        patients.filter { patientQuery.isEmpty || ($0.name + " " + $0.record).localizedCaseInsensitiveContains(patientQuery) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PatientFormCard(titulo: "Historial clínico", icono: "clock.arrow.circlepath") {
                Text("Tus consultas con el paciente seleccionado.").font(.footnote).foregroundStyle(HospitalTheme.secondary)
                TextField("Buscar paciente o expediente", text: $patientQuery).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Buscar paciente o expediente")
                Text("Pacientes de la agenda seleccionada").font(.caption).foregroundStyle(HospitalTheme.secondary)
                if matchingPatients.isEmpty { Text("No hay pacientes que coincidan.").font(.footnote) }
                ForEach(matchingPatients) { patient in
                    Button {
                        selected = patient.id
                        Task { await searchHistory() }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(patient.name).font(.subheadline.weight(.semibold))
                                Text(patient.record).font(.caption)
                            }
                            Spacer()
                            Image(systemName: selected == patient.id ? "checkmark.circle.fill" : "circle")
                        }.foregroundStyle(HospitalTheme.wine).padding(12)
                            .background(selected == patient.id ? HospitalTheme.rose : HospitalTheme.background, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).accessibilityAddTraits(selected == patient.id ? .isSelected : [])
                }
                Toggle("Filtrar por fecha", isOn: $filterDates)
                if filterDates {
                    DatePicker("Desde", selection: $from, displayedComponents: .date)
                    DatePicker("Hasta", selection: $to, displayedComponents: .date)
                }
                Button("Buscar consultas") { Task { await searchHistory() } }
                    .buttonStyle(.bordered).disabled(selected == nil || loading)
                if let patient = patients.first(where: { $0.id == selected }) {
                    Text("Consultas con \(patient.name)").font(.subheadline.weight(.semibold))
                } else { Text("Selecciona un paciente para consultar su historial.").font(.footnote) }
                if loading { ProgressView("Buscando consultas…") }
                if let error { Text(error).font(.footnote).foregroundStyle(HospitalTheme.wine) }
                if searched && !loading && error == nil && history.isEmpty { Text("No hay consultas propias en este intervalo.").font(.footnote) }
                ForEach(history) { visit in
                    HospitalCard {
                        Text(DoctorDate.display(visit.started_at)).font(.subheadline.weight(.semibold))
                        Text(visit.subjective ?? "Consulta sin nota registrada").font(.footnote)
                        if let plan = visit.plan { Text(plan).font(.footnote).foregroundStyle(HospitalTheme.secondary) }
                        Text(visit.status == "closed" ? "Finalizada" : "En curso").font(.caption).foregroundStyle(HospitalTheme.wine)
                    }.overlay(RoundedRectangle(cornerRadius: 14).stroke(HospitalTheme.rose, lineWidth: 1))
                }
            }
            .onChange(of: filterDates) { _, _ in invalidateHistory() }
            .onChange(of: from) { _, _ in invalidateHistory() }
            .onChange(of: to) { _, _ in invalidateHistory() }
        }
        .onDisappear { invalidateHistory() }
        .onChange(of: patients.map(\.id)) { _, _ in selected = nil; invalidateHistory() }
    }

    private func invalidateHistory() {
        request = UUID(); history = []; searched = false; error = nil; loading = false
    }
    @MainActor private func searchHistory() async {
        guard let selected else { return }
        invalidateHistory()
        guard !filterDates || from <= to else { error = "La fecha inicial no puede ser posterior a la final."; return }
        let token = request
        loading = true
        defer { if token == request { loading = false } }
        do {
            let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: to))!
                .addingTimeInterval(-0.001)
            let rows = try await loadHistory(selected, filterDates ? Calendar.current.startOfDay(for: from) : nil, filterDates ? end : nil)
            guard token == request, !Task.isCancelled else { return }
            history = rows.sorted { $0.started_at > $1.started_at }; searched = true
        } catch {
            guard token == request else { return }
            self.error = "No se pudo cargar el historial. Intenta buscar de nuevo."
        }
    }
}


#Preview("Pacientes · historial local") {
    ScrollView {
        DoctorPatientHistoryView(patients: DoctorDashboardDemo.patients,
            loadHistory: { patient, from, to in DoctorDashboardDemo.history(patient: patient, from: from, to: to) })
            .padding(17)
    }.background(HospitalTheme.background)
}
