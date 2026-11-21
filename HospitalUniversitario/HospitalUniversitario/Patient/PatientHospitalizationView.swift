import SwiftUI

/// Hospitalizaciones presentadas por HospitalCore.hospitalizations (misma lógica que web `patientRooms`).
/// Activa = asignado/hospitalizado; alta_medica y cerrado son «Hospitalizaciones anteriores». Solo campos registrados.
struct PatientHospitalizations: Decodable, Equatable {
    let active: HospitalizationEpisode?
    let previous: [HospitalizationEpisode]
}

struct HospitalizationEpisode: Decodable, Equatable, Identifiable {
    struct Row: Decodable, Equatable { let label: String; let value: String }
    struct Section: Decodable, Equatable { let title: String; let rows: [Row] }
    struct Transfer: Decodable, Equatable { let room: String?; let room_kind: String?; let bed: String?; let from: String; let until: String? }
    let id: String
    let status: String
    let status_label: String
    let active: Bool
    let hospital: String?
    let room: String?
    let room_kind: String?
    let bed: String?
    let area: String?
    let doctor: String?
    let specialty: String?
    let admitted_date: String?
    let admitted_time: String?
    let discharged_date: String?
    let discharged_time: String?
    let sections: [Section]
    let transfers: [Transfer]

    var roomTitle: String { room.map { "Habitación \($0)" } ?? "Habitación por confirmar" }
    var subtitle: String { [room_kind, hospital].compactMap { $0 }.joined(separator: " · ") }
}

/// Contenido de la pantalla existente «Habitaciones» (ruta `rooms`) para el paciente. No es una pantalla nueva.
struct PatientHospitalizationView: View {
    let data: PatientHospitalizations?
    let error: String?
    let linked: Bool
    let loading: Bool
    let search: String
    let retry: () -> Void
    @State private var selected: HospitalizationEpisode?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let error {
                Text(error).font(.subheadline).foregroundStyle(HospitalTheme.ink).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Button("Reintentar", action: retry).buttonStyle(.bordered).tint(HospitalTheme.wine)
            } else if loading && data == nil {
                ProgressView("Cargando tu hospitalización…").frame(maxWidth: .infinity)
            } else if !linked {
                emptyState("Recepción debe vincular tu expediente para mostrar tus hospitalizaciones.")
            } else {
                if let active = data?.active, hit(active) {
                    sectionTitle("Tu hospitalización actual")
                    Button { selected = active } label: { activeCard(active) }.buttonStyle(.plain)
                } else if data?.active == nil {
                    emptyState("Cuando el personal autorizado registre un ingreso, aparecerá aquí con tu habitación y médico responsable.")
                }
                let previous = (data?.previous ?? []).filter(hit)
                if !previous.isEmpty {
                    sectionTitle("Hospitalizaciones anteriores").padding(.top, 6)
                    ForEach(previous) { item in
                        Button { selected = item } label: { pastRow(item) }.buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(item: $selected) { item in HospitalizationDetailView(episode: item) }
    }

    private func hit(_ e: HospitalizationEpisode) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return [e.room, e.room_kind, e.admitted_date, e.status_label].compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains(q) }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.headline).foregroundStyle(HospitalTheme.ink)
    }

    private func emptyState(_ detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "bed.double").font(.title2).foregroundStyle(HospitalTheme.wine).frame(width: 58, height: 58).background(HospitalTheme.rose, in: Circle())
            Text("Actualmente no tienes una hospitalización registrada").font(.headline).multilineTextAlignment(.center).foregroundStyle(HospitalTheme.ink)
            Text(detail).font(.subheadline).multilineTextAlignment(.center).foregroundStyle(HospitalTheme.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 28).padding(.horizontal, 18).frame(maxWidth: .infinity)
            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func activeCard(_ e: HospitalizationEpisode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TU HOSPITALIZACIÓN ACTUAL").font(.caption2.weight(.heavy)).tracking(1.2).opacity(0.85)
            Text(e.roomTitle).font(.title2.bold())
            if !e.subtitle.isEmpty { Text(e.subtitle).font(.subheadline).opacity(0.9) }
            Text(e.status_label).font(.caption.bold()).foregroundStyle(HospitalTheme.wine).padding(.horizontal, 10).padding(.vertical, 4).background(.white, in: Capsule())
            HospitalizationFacts(rows: [("Ingreso", [e.admitted_date, e.admitted_time].compactMap { $0 }.joined(separator: " · ")),
                                        ("Médico", [e.doctor, e.specialty].compactMap { $0 }.joined(separator: " · ")),
                                        ("Área", e.area ?? ""), ("Cama", e.bed ?? "")], light: true)
                .padding(12).background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack { Spacer(); Text("Ver detalles").font(.subheadline.weight(.semibold)); Image(systemName: "chevron.right").font(.caption.bold()) }
        }.foregroundStyle(.white).padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient.vinoDestacado, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityElement(children: .combine).accessibilityHint("Abre los detalles de tu hospitalización")
    }

    private func pastRow(_ e: HospitalizationEpisode) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bed.double").foregroundStyle(HospitalTheme.wine).frame(width: 38, height: 38).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text([e.roomTitle, e.room_kind].compactMap { $0 }.joined(separator: " · ")).font(.subheadline.weight(.semibold)).foregroundStyle(HospitalTheme.ink)
                Text("Ingreso: \(e.admitted_date ?? "sin fecha")" + (e.discharged_date.map { " · Alta: \($0)" } ?? "")).font(.caption).foregroundStyle(HospitalTheme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            HospitalBadge(text: e.status_label, warning: false)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(HospitalTheme.secondary)
        }.padding(14).frame(minHeight: 60).background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct HospitalizationFacts: View {
    let rows: [(String, String)]
    var light = false
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: 10) {
            ForEach(rows.filter { !$0.1.isEmpty }, id: \.0) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.0).font(.caption2).foregroundStyle(light ? .white.opacity(0.75) : HospitalTheme.secondary)
                    Text(row.1).font(.footnote.weight(.semibold)).foregroundStyle(light ? .white : HospitalTheme.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Detalle de un episodio (activo o finalizado). Las secciones vienen ya filtradas sin campos vacíos.
struct HospitalizationDetailView: View {
    let episode: HospitalizationEpisode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(episode.active ? "TU HOSPITALIZACIÓN ACTUAL" : "HOSPITALIZACIÓN FINALIZADA").font(.caption2.weight(.heavy)).tracking(1.2).opacity(0.85)
                        Text(episode.roomTitle).font(.title2.bold())
                        if !episode.subtitle.isEmpty { Text(episode.subtitle).font(.subheadline).opacity(0.9) }
                        Text(episode.status_label).font(.caption.bold()).foregroundStyle(HospitalTheme.wine).padding(.horizontal, 10).padding(.vertical, 4).background(.white, in: Capsule())
                    }.foregroundStyle(.white).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(episode.active ? AnyShapeStyle(LinearGradient.vinoDestacado) : AnyShapeStyle(Color(red: 0.3, green: 0.33, blue: 0.4)), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    ForEach(episode.sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title).font(.subheadline.bold()).foregroundStyle(HospitalTheme.wine)
                            HospitalizationFacts(rows: section.rows.map { ($0.label, $0.value) })
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    if !episode.transfers.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Traslados de habitación").font(.subheadline.bold()).foregroundStyle(HospitalTheme.wine)
                            ForEach(Array(episode.transfers.enumerated()), id: \.offset) { _, t in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text([t.room.map { "Habitación \($0)" } ?? "Habitación", t.room_kind].compactMap { $0 }.joined(separator: " · ")).font(.footnote.weight(.semibold))
                                    Text("Desde \(t.from)" + (t.until.map { " · hasta \($0)" } ?? " · actual")).font(.caption).foregroundStyle(HospitalTheme.secondary)
                                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }.padding(16)
            }
            .background(HospitalTheme.background)
            .navigationTitle("Detalle de hospitalización").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() } } }
        }
    }
}
