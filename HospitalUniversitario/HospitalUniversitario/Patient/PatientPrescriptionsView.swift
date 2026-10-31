import SwiftUI

struct PatientPrescriptionMedicine: Codable {
    let name: String
    let dose: String
    let frequency: String
    let route: String
    let duration: String
    let quantity: String
    let observations: String
}
struct PatientPrescriptionRecord: Identifiable, Codable {
    let id: String
    let issuedAt: String
    let dateLabel: String
    let pickup: String
    let medicines: [PatientPrescriptionMedicine]
    static let missing = "No hay datos reales"
    static let examples: [Self] = [
        .init(id: "rx-demo-1", issuedAt: "2026-10-30T09:00:00-06:00", dateLabel: "30 oct 2026", pickup: "Pendiente", medicines: [
            .init(name: "MEDICAMENTO DE EJEMPLO", dose: "1 unidad", frequency: "24 horas", route: "Oral", duration: "5 días", quantity: "5 unidades", observations: "Ejemplo de receta pendiente de retirar.")]),
        .init(id: "rx-demo-2", issuedAt: "2026-10-01T14:25:00-06:00", dateLabel: "1 oct 2026", pickup: "Retirada", medicines: [
            .init(name: "CLARITROMICINA 500 MG / TABLETA", dose: "1 tableta", frequency: "12 horas", route: "Oral", duration: "10 días", quantity: "20 tabletas", observations: "Datos ilustrativos de la referencia visual.")])
    ]
    static func from(_ item: MobileItem) -> Self {
        let state = item.details.first { $0.label.localizedCaseInsensitiveCompare("Estado de retiro") == .orderedSame }?.value.lowercased() ?? item.status.lowercased()
        let normalized = state.trimmingCharacters(in: .whitespacesAndNewlines)
        let pickup = ["retirada", "dispensed", "collected", "withdrawn"].contains(normalized) ? "Retirada" : ["pendiente", "pickup_pending", "pending"].contains(normalized) ? "Pendiente" : "Retiro por confirmar"
        let format = DateFormatter(); format.locale = Locale(identifier: "es_GT"); format.timeZone = TimeZone(identifier: "America/Guatemala"); format.dateFormat = "d MMM yyyy"
        let rows = item.details.filter { $0.label.localizedCaseInsensitiveCompare("Estado de retiro") != .orderedSame }.map {
            PatientPrescriptionMedicine(name: $0.label, dose: missing, frequency: missing, route: missing, duration: missing, quantity: missing, observations: $0.value.isEmpty ? missing : $0.value)
        }
        return .init(id: item.id.uuidString, issuedAt: item.event_at, dateLabel: DoctorDate.parse(item.event_at).map { format.string(from: $0) } ?? missing,
            pickup: pickup, medicines: rows.isEmpty ? [.init(name: item.title, dose: missing, frequency: missing, route: missing, duration: missing, quantity: missing, observations: item.subtitle ?? missing)] : rows)
    }
}
struct PatientPrescriptionsView: View {
    let records: [PatientPrescriptionRecord]
    let demonstration: Bool
    let search: String
    var loading = false
    var error: String? = nil
    var hasMore = false
    var retry: () -> Void = {}
    var loadMore: () -> Void = {}
    private var filtered: [PatientPrescriptionRecord] {
        records.filter { record in search.isEmpty || (record.dateLabel + " " + record.pickup + " " + record.medicines.map { $0.name + " " + $0.observations }.joined(separator: " ")).localizedStandardContains(search) }
            .sorted { (DoctorDate.parse($0.issuedAt) ?? .distantPast) > (DoctorDate.parse($1.issuedAt) ?? .distantPast) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Mis recetas").font(.system(size: 22, weight: .bold)).foregroundStyle(HospitalTheme.ink)
            if demonstration { Text("Recetas de ejemplo · No corresponden a una prescripción real").font(.caption).foregroundStyle(HospitalTheme.secondary) }
            if loading { ProgressView("Cargando tus recetas…") }
            if let error { Text(error).font(.footnote); Button("Reintentar", action: retry) }
            if filtered.isEmpty && !loading && error == nil { HospitalCard { Text("No hay recetas para mostrar.").font(.subheadline); Text("Tus recetas aparecerán aquí cuando estén disponibles.").font(.footnote).foregroundStyle(HospitalTheme.secondary) } }
            ForEach(filtered) { record in
                Text(record.dateLabel).font(.subheadline.weight(.semibold)).foregroundStyle(HospitalTheme.secondary)
                ForEach(Array(record.medicines.enumerated()), id: \.offset) { _, medicine in
                    VStack(alignment: .leading, spacing: 18) {
                        Text(record.pickup).font(.subheadline.weight(.semibold)).foregroundStyle(HospitalTheme.wine).padding(.horizontal, 12).padding(.vertical, 6)
                            .background(record.pickup == "Retirada" ? HospitalTheme.green : record.pickup == "Pendiente" ? Color(red: 1, green: 0.95, blue: 0.85) : HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 7))
                        Label(medicine.name, systemImage: "pills").font(.system(size: 16, weight: .bold)).foregroundStyle(HospitalTheme.ink).fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: 12) {
                            row("Dosis", medicine.dose); line
                            row("Cada", medicine.frequency); line
                            row("Vía", medicine.route); line
                            row("Durante", medicine.duration); line
                            row("Cantidad", medicine.quantity); line
                        }
                        DoctorConsultationField(label: "Observaciones", value: medicine.observations)
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(HospitalTheme.rose, lineWidth: 1))
                }
            }
            if hasMore { Button("Cargar más", action: loadMore).disabled(loading) }
        }
    }
    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 14) { Text(label + ":").font(.subheadline.weight(.semibold)); Spacer(minLength: 0); Text(value).font(.footnote).multilineTextAlignment(.trailing) }.foregroundStyle(HospitalTheme.secondary)
    }
    private var line: some View { Rectangle().stroke(HospitalTheme.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1) }
}
#Preview("Recetas del paciente") { ScrollView { PatientPrescriptionsView(records: PatientPrescriptionRecord.examples, demonstration: true, search: "").padding(17) }.background(HospitalTheme.background) }
