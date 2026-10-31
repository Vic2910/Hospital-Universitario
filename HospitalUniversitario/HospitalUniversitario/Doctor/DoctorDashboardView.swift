import SwiftUI

struct DoctorDashboardPatient: Identifiable {
    let id: UUID
    let name: String
    let record: String
}

/// Presentación compartida por la sesión real y el Preview local, sin autenticación alternativa.
struct DoctorDashboardView: View {
    let name: String
    let facility: String
    let consultationCount: Int
    var demonstration = false
    let navigate: (String) -> Void
    private var initials: String {
        name.split(separator: " ").filter { !["Dr.", "Dra."].contains(String($0)) }
            .prefix(2).compactMap(\.first).map { String($0) }.joined().uppercased()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HospitalCard {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hola, \(name)").font(.system(size: 22, weight: .bold))
                        Text("Tu jornada clínica, en un solo lugar.").font(.system(size: 12)).foregroundStyle(HospitalTheme.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(initials).font(.system(size: 18, weight: .semibold)).foregroundStyle(HospitalTheme.wine)
                        .frame(width: 58, height: 58).background(HospitalTheme.rose, in: Circle())
                        .accessibilityLabel("Iniciales de \(name)")
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Label("HOY", systemImage: "calendar").font(.system(size: 10, weight: .bold)).tracking(1)
                Text(Date().formatted(.dateTime.locale(Locale(identifier: "es_GT")).weekday(.wide).day().month(.wide))).font(.system(size: 14, weight: .semibold))
                Divider().overlay(.white.opacity(0.25))
                Text("\(consultationCount)").font(.system(size: 36, weight: .bold))
                Text("Consultas programadas para hoy").font(.system(size: 13, weight: .semibold))
                Text(facility).font(.system(size: 12))
            }
            .foregroundStyle(.white).padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient.vinoDestacado, in: RoundedRectangle(cornerRadius: 18))
            if demonstration {
                Text("Modo diseño · Doctor y datos ficticios. Sin conexión al hospital.").font(.footnote).foregroundStyle(HospitalTheme.secondary)
            }
            Text("Accesos rápidos").font(.system(size: 16, weight: .semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                PatientQuickAccessCard(icono: "person.2", titulo: "Pacientes") { navigate("patients") }
                PatientQuickAccessCard(icono: "cross.case", titulo: "Consultas") { navigate("consultation") }
                PatientQuickAccessCard(icono: "testtube.2", titulo: "Laboratorios") { navigate("laboratory") }
                PatientQuickAccessCard(icono: "doc.text", titulo: "Expedientes") { navigate("chart") }
            }
        }.foregroundStyle(HospitalTheme.ink)
    }
}

/// Fixtures exclusivas del Preview: mismo contenido que doctor-dashboard.js.
enum DoctorDashboardDemo {
    static let patientA = UUID(uuidString: "00000000-0000-4000-8000-000000000101")!
    static let patientB = UUID(uuidString: "00000000-0000-4000-8000-000000000102")!
    static let patients = [DoctorDashboardPatient(id: patientA, name: "Carlos Mendoza", record: "DEMO-101"),
                           DoctorDashboardPatient(id: patientB, name: "María López", record: "DEMO-102")]
    static func history(patient: UUID, from: Date?, to: Date?) -> [DoctorConsultation] {
        let rows: [(UUID, String, Int, String, String)] = [
            (patientA, "doctor-demo", -1, "Consulta de seguimiento", "Seguimiento registrado en modo diseño."),
            (patientA, "doctor-demo", -7, "Revisión de resultados", "Resultados revisados en modo diseño."),
            (patientB, "doctor-demo", -2, "Consulta general", "Control registrado en modo diseño."),
            (patientA, "otro-doctor", -1, "Consulta ajena que debe excluirse", "No mostrar")]
        return rows.enumerated().compactMap { index, row in
            let date = Calendar.current.date(byAdding: .day, value: row.2, to: Calendar.current.startOfDay(for: Date()))!.addingTimeInterval(9 * 3600)
            guard row.0 == patient, row.1 == "doctor-demo", from.map({ date >= $0 }) ?? true, to.map({ date <= $0 }) ?? true else { return nil }
            return DoctorConsultation(id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 201))!, started_at: DoctorDate.timestamp(date), status: "closed", subjective: row.3, objective: nil, assessment: nil, plan: row.4, note_id: nil, note_version: nil, row_version: 1)
        }
    }
}

#Preview("Doctor · datos locales") {
    ScrollView {
        DoctorDashboardView(name: "Dr. Luis Ramírez", facility: "Sede Central · Medicina interna", consultationCount: 4,
            demonstration: true, navigate: { _ in })
            .padding(17)
    }.background(HospitalTheme.background).environment(\.locale, Locale(identifier: "es_GT"))
}
