import SwiftUI

/// Consulta finalizada del propio paciente (my_consultation_history vía HospitalCore). Paridad con web-preview/patient-history.js.
struct PatientHistoryRecord: Identifiable, Codable {
    let id: String
    let startedAt: String
    let dateLabel: String
    let timeLabel: String
    let specialty: String
    let doctor: String
    let reason: String
    var diagnosis: String = ""
    var details: [MobileField] = []
    static let examples: [Self] = [
        .init(id: "history-demo-1", startedAt: "2026-10-01T14:25:00-06:00", dateLabel: "1 oct 2026", timeLabel: "14:25", specialty: "Dermatología", doctor: "Dra. Marta Romero", reason: "Citada dermatológico"),
        .init(id: "history-demo-2", startedAt: "2026-09-02T13:30:00-06:00", dateLabel: "2 sept 2026", timeLabel: "13:30", specialty: "Cardiología", doctor: "Dr. Diego Santos", reason: "Consulta cardiológica"),
        .init(id: "history-demo-3", startedAt: "2026-04-15T08:35:00-06:00", dateLabel: "15 abr 2026", timeLabel: "08:35", specialty: "Medicina general", doctor: "Dra. Laura Campos", reason: "Revisión general")
    ]
    static let physical = ["Peso (kg)", "Altura (cm)", "Temperatura (°C)", "Presión sistólica (mmHg)", "Presión diastólica (mmHg)", "Frecuencia cardíaca (lpm)"]
    static let evaluation = ["Motivo de consulta", "Síntomas que presentaba", "Diagnóstico", "Código diagnóstico", "Observaciones", "Tratamiento"]

    static func from(_ item: MobileItem) -> Self {
        let details = item.details.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        func value(_ labels: [String]) -> String {
            (details.first { field in labels.contains { field.label.localizedCaseInsensitiveCompare($0) == .orderedSame } }?.value ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let date = DoctorDate.parse(item.event_at)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "es_SV"); formatter.timeZone = DoctorClinicalRules.timeZone
        formatter.dateFormat = "d MMM yyyy"; let day = date.map { formatter.string(from: $0) } ?? "Fecha no disponible"
        formatter.dateFormat = "HH:mm"; let time = date.map { formatter.string(from: $0) } ?? ""
        let specialty = value(["Especialidad"]), doctor = value(["Médico"])
        return .init(id: item.id.uuidString, startedAt: item.event_at, dateLabel: day, timeLabel: time,
            specialty: specialty.isEmpty ? (item.title.isEmpty ? "Consulta médica" : item.title) : specialty,
            doctor: doctor.isEmpty ? "Médico responsable" : doctor,
            reason: value(["Motivo de consulta", "Motivo"]), diagnosis: value(["Diagnóstico"]), details: details)
    }

    /// Detalle agrupado; solo campos con valor real.
    var groups: [(title: String, icon: String, fields: [MobileField])] {
        let real = details.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let values: [(String, String, [MobileField])] = [
            ("Datos físicos", "figure.stand", real.filter { Self.physical.contains($0.label) }),
            ("Evaluación médica", "stethoscope", Self.evaluation.flatMap { label in real.filter { $0.label == label } }),
            ("Recetas", "pills.fill", real.filter { $0.label.hasPrefix("Receta") }),
            ("Exámenes", "testtube.2", real.filter { $0.label.hasPrefix("Examen") })]
        return values.filter { !$0.2.isEmpty }.map { (title: $0.0, icon: $0.1, fields: $0.2) }
    }
}

/// Lectura del historial propio: tarjetas cronológicas y detalle interno, sin escrituras.
struct PatientHistoryView: View {
    let records: [PatientHistoryRecord]
    let demonstration: Bool
    let search: String
    var loading = false
    var error: String? = nil
    var hasMore = false
    var retry: () -> Void = {}
    var loadMore: () -> Void = {}
    @State private var selectedID: String?
    private var ordered: [PatientHistoryRecord] {
        records.sorted { (DoctorDate.parse($0.startedAt) ?? .distantPast) > (DoctorDate.parse($1.startedAt) ?? .distantPast) }
    }
    private var matches: [PatientHistoryRecord] {
        ordered.filter { search.isEmpty || ($0.dateLabel + " " + $0.specialty + " " + $0.doctor + " " + $0.reason + " " + $0.diagnosis).localizedStandardContains(search) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if loading { ProgressView("Cargando tu historial…").frame(maxWidth: .infinity) }
            if let error { HospitalCard { Text(error).font(.footnote); Button("Reintentar", action: retry) } }
            if let record = ordered.first(where: { $0.id == selectedID }) { detail(record) }
            else { list }
        }.tint(HospitalTheme.wine)
        .onChange(of: records.map(\.id)) { _, ids in if let selectedID, !ids.contains(selectedID) { self.selectedID = nil } }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Label("MI HISTORIAL MÉDICO", systemImage: "clock.arrow.circlepath").font(.caption.bold()).tracking(1.2)
                Text("Tus consultas finalizadas").font(.title2.bold())
                Text("De la más reciente a la más antigua. Solo tú y tu médico pueden ver esta información.").font(.subheadline).opacity(0.9)
            }.foregroundStyle(.white).padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient.vinoDestacado, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            if demonstration { exampleNotice }
            if matches.isEmpty && !loading && error == nil {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass").font(.system(size: 32, weight: .semibold)).foregroundStyle(HospitalTheme.wine)
                        .frame(width: 68, height: 68).background(HospitalTheme.rose, in: Circle())
                    Text(search.isEmpty ? "Todavía no tienes historial de consultas" : "Sin coincidencias").font(.headline)
                    Text(search.isEmpty ? "Tus consultas aparecerán aquí cuando el médico las finalice." : "No encontramos consultas con esa búsqueda. Prueba con otra fecha, especialidad o médico.")
                        .font(.subheadline).foregroundStyle(HospitalTheme.secondary).multilineTextAlignment(.center)
                }.padding(24).frame(maxWidth: .infinity).background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            ForEach(matches) { record in
                Button { selectedID = record.id } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(record.dateLabel).font(.system(size: 16, weight: .bold)).foregroundStyle(HospitalTheme.ink)
                            Spacer(); Text(record.timeLabel).font(.system(size: 14, weight: .medium)).foregroundStyle(HospitalTheme.wine)
                        }
                        Label("\(record.doctor) · \(record.specialty)", systemImage: "stethoscope").font(.caption).foregroundStyle(HospitalTheme.secondary)
                        if !record.reason.isEmpty { line("Motivo", record.reason) }
                        if !record.diagnosis.isEmpty { line("Diagnóstico", record.diagnosis) }
                        HStack { Spacer(); Label("Ver detalle", systemImage: "chevron.right").font(.caption.bold()).foregroundStyle(HospitalTheme.wine) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18).padding(.leading, 6)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 3).fill(HospitalTheme.wine).frame(width: 5).padding(.vertical, 10) }
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(HospitalTheme.ink.opacity(0.06), lineWidth: 1))
                        .shadow(color: HospitalTheme.ink.opacity(0.04), radius: 8, y: 3)
                }.buttonStyle(.plain).accessibilityLabel("Ver consulta del \(record.dateLabel) con \(record.doctor)")
            }
            if hasMore { Button("Cargar consultas anteriores", action: loadMore).frame(maxWidth: .infinity).disabled(loading) }
        }
    }

    private func detail(_ record: PatientHistoryRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { selectedID = nil } label: { Label("Volver a mi historial", systemImage: "chevron.left").font(.subheadline.weight(.semibold)) }
            VStack(alignment: .leading, spacing: 8) {
                Text("Detalle de consulta").font(.caption.bold()).tracking(1).opacity(0.85)
                Text(record.dateLabel + (record.timeLabel.isEmpty ? "" : " · \(record.timeLabel)")).font(.title3.bold())
                Label(record.doctor, systemImage: "stethoscope").font(.subheadline)
                Label(record.specialty, systemImage: "cross.case").font(.subheadline)
            }.foregroundStyle(.white).padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient.vinoDestacado, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            if demonstration { exampleNotice }
            let groups = record.groups
            if groups.isEmpty {
                Text("Esta consulta no tiene información clínica adicional publicada.").font(.subheadline).foregroundStyle(HospitalTheme.secondary)
            }
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 12) {
                    Label(group.title, systemImage: group.icon).font(.headline).foregroundStyle(HospitalTheme.ink)
                    ForEach(Array(group.fields.enumerated()), id: \.offset) { _, field in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.label).font(.caption.weight(.semibold)).foregroundStyle(HospitalTheme.secondary)
                            Text(field.value).font(.body).foregroundStyle(HospitalTheme.ink).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            if !groups.contains(where: { $0.title == "Recetas" || $0.title == "Exámenes" }) {
                Text("Tus recetas y resultados también están disponibles en Mis recetas y Mis laboratorios.").font(.footnote).foregroundStyle(HospitalTheme.secondary)
            }
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(HospitalTheme.secondary)
            Text(value).font(.system(size: 13)).foregroundStyle(HospitalTheme.ink).lineLimit(3)
        }
    }
    private var exampleNotice: some View {
        Text("Datos de ejemplo · No son registros clínicos reales").font(.caption).foregroundStyle(HospitalTheme.secondary)
    }
}
#Preview("Historial médico · Paciente") { ScrollView { PatientHistoryView(records: PatientHistoryRecord.examples, demonstration: true, search: "").padding(17) }.background(HospitalTheme.background) }
