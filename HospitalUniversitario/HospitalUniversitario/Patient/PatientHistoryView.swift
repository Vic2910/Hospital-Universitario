import SwiftUI

struct PatientHistoryRecord: Identifiable, Codable {
    let id: String
    let startedAt: String
    let dateLabel: String
    let timeLabel: String
    let specialty: String
    let doctor: String
    let reason: String
    var details: [MobileField] = []
    static let examples: [Self] = [
        .init(id: "history-demo-1", startedAt: "2026-10-01T14:25:00-06:00", dateLabel: "1 oct 2026", timeLabel: "14:25", specialty: "Dermatología", doctor: "Dra. Marta Romero", reason: "Citada dermatológico"),
        .init(id: "history-demo-2", startedAt: "2026-09-02T13:30:00-06:00", dateLabel: "2 sept 2026", timeLabel: "13:30", specialty: "Cardiología", doctor: "Dr. Diego Santos", reason: "Consulta cardiológica"),
        .init(id: "history-demo-3", startedAt: "2026-04-15T08:35:00-06:00", dateLabel: "15 abr 2026", timeLabel: "08:35", specialty: "Medicina general", doctor: "Dra. Laura Campos", reason: "Revisión general")
    ]
    static func from(_ item: MobileItem) -> Self {
        func value(_ labels: [String], fallback: String? = nil) -> String {
            let text = item.details.first { field in labels.contains { field.label.localizedCaseInsensitiveCompare($0) == .orderedSame } }?.value ?? fallback ?? ""
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? "No hay datos reales" : clean
        }
        let date = DoctorDate.parse(item.event_at)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "es_GT"); formatter.timeZone = TimeZone(identifier: "America/Guatemala")
        formatter.dateFormat = "d MMM yyyy"; let day = date.map { formatter.string(from: $0) } ?? "No hay datos reales"
        formatter.dateFormat = "HH:mm"; let time = date.map { formatter.string(from: $0) } ?? "No hay datos reales"
        return .init(id: item.id.uuidString, startedAt: item.event_at, dateLabel: day, timeLabel: time,
            specialty: value(["Especialidad"], fallback: item.title), doctor: value(["Médico", "Doctor", "Doctor solicitante"]),
            reason: value(["Motivo", "Motivo de consulta"], fallback: item.subtitle), details: item.details)
    }
}

/// Lectura del historial propio: tarjetas y detalle interno, sin escrituras.
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
        ordered.filter { search.isEmpty || ($0.dateLabel + " " + $0.specialty + " " + $0.doctor + " " + $0.reason).localizedStandardContains(search) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if loading { ProgressView("Cargando tu historial…") }
            if let error { HospitalCard { Text(error).font(.footnote); Button("Reintentar", action: retry) } }
            if let record = ordered.first(where: { $0.id == selectedID }) {
                VStack(spacing: 22) {
                    HStack { Button("Volver") { selectedID = nil }; Spacer(); Text("MI HISTORIAL").font(.caption).foregroundStyle(HospitalTheme.secondary) }
                    Image(systemName: "doc.text.magnifyingglass").font(.system(size: 30)).foregroundStyle(.white)
                        .frame(width: 72, height: 72).background(HospitalTheme.wine, in: Circle()).accessibilityHidden(true)
                    Text("Detalle de consulta").font(.system(size: 26, weight: .bold))
                    VStack(spacing: 8) { Text(record.dateLabel).font(.headline); Text(record.timeLabel).font(.headline) }
                        .padding(18).frame(maxWidth: .infinity).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 16))
                    if demonstration { exampleNotice }
                    VStack(alignment: .leading, spacing: 18) {
                        DoctorConsultationField(label: "Especialidad", value: record.specialty)
                        DoctorConsultationField(label: "Médico", value: record.doctor)
                        DoctorConsultationField(label: "Motivo de la consulta", value: record.reason)
                        ForEach(Array(record.details.enumerated()), id: \.offset) { _, field in DoctorConsultationField(label: field.label, value: field.value.isEmpty ? "No hay datos reales" : field.value) }
                    }
                }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 22))
            } else {
                Text("Mis consultas").font(.system(size: 18, weight: .semibold)).foregroundStyle(HospitalTheme.ink)
                if demonstration { exampleNotice }
                if matches.isEmpty && !loading && error == nil {
                    HospitalCard {
                        Text("Tu historial está listo para acompañarte").font(.subheadline.weight(.semibold))
                        Text(search.isEmpty ? "Aún no hay consultas registradas. Aparecerán aquí cuando estén disponibles." : "No encontramos consultas con esa búsqueda. Prueba con otra fecha, especialidad o médico.").font(.footnote).foregroundStyle(HospitalTheme.secondary)
                    }
                }
                ForEach(matches) { record in
                    Button { selectedID = record.id } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(record.dateLabel).font(.system(size: 16, weight: .bold)).foregroundStyle(HospitalTheme.ink)
                                Spacer(); Text(record.timeLabel).font(.system(size: 14, weight: .medium)).foregroundStyle(HospitalTheme.secondary)
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(record.specialty).font(.system(size: 12)).foregroundStyle(HospitalTheme.secondary)
                                Text(record.doctor).font(.system(size: 15, weight: .semibold)).foregroundStyle(HospitalTheme.ink)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Motivo").font(.system(size: 10, weight: .semibold)).foregroundStyle(HospitalTheme.secondary)
                                Text(record.reason).font(.system(size: 13)).foregroundStyle(HospitalTheme.ink)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).padding(.leading, 6)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 3).fill(HospitalTheme.green).frame(width: 5).padding(.vertical, 10) }
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(HospitalTheme.ink.opacity(0.06), lineWidth: 1))
                            .shadow(color: HospitalTheme.ink.opacity(0.04), radius: 8, y: 3)
                    }.buttonStyle(.plain).accessibilityLabel("Ver consulta del \(record.dateLabel) con \(record.doctor)")
                }
                if hasMore { Button("Cargar más", action: loadMore).disabled(loading) }
            }
        }.tint(HospitalTheme.wine)
        .onChange(of: records.map(\.id)) { _, ids in if let selectedID, !ids.contains(selectedID) { self.selectedID = nil } }
    }
    private var exampleNotice: some View {
        Text("Datos de ejemplo · No son registros clínicos reales").font(.caption).foregroundStyle(HospitalTheme.secondary)
    }
}
#Preview("Historial médico · Paciente") { ScrollView { PatientHistoryView(records: PatientHistoryRecord.examples, demonstration: true, search: "").padding(17) }.background(HospitalTheme.background) }
