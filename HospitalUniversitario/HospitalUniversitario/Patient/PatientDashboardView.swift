import SwiftUI

/// Datos autorizados de la próxima cita, adaptados por el núcleo compartido.
struct PatientDashboardData: Decodable {
    let next_appointment: ProximaCita?
}
struct ProximaCita: Identifiable, Equatable, Decodable {
    let id: UUID
    let starts_at: String
    let ends_at: String
    let status: String
    let doctor_name: String?
    private func formatted(_ format: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: starts_at) ?? ISO8601DateFormatter().date(from: starts_at) else { return "Horario no disponible" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_GT")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
    var dia: String { formatted("EEEE d 'de' MMMM") }
    var hora: String { formatted("h:mm a") }
    var medico: String { doctor_name ?? "Nombre del médico no disponible" }
}

/// Dashboard principal del paciente: saludo, card de fecha con próxima cita
/// y accesos rápidos. Se integra dentro de la portal existente, respetando su
/// encabezado y la barra de navegación inferior del rol.
struct PatientDashboardView: View {
    /// Primer nombre y primer apellido obtenidos del perfil real.
    var nombrePaciente: String
    /// Próxima cita del paciente, si existe.
    var proximaCita: ProximaCita?
    var sinExpediente = false
    var cargando = false
    var error: String? = nil
    var retry: () -> Void = {}
    /// Navegación hacia los destinos del catálogo (mismo sistema que el resto de la app).
    var navigate: (String) -> Void

    /// Iniciales del nombre real para el avatar.
    private var iniciales: String {
        String(nombrePaciente
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map { String($0).uppercased() }
            .joined())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PatientGreetingCard(nombre: nombrePaciente, iniciales: iniciales.isEmpty ? "HU" : iniciales)
            PatientDateAppointmentCard(proximaCita: proximaCita, cargando: cargando, error: error)
            if error != nil {
                Button("Reintentar", action: retry).font(.subheadline.weight(.semibold))
            }
            if sinExpediente {
                Label("Recepción debe crear o vincular tu expediente. Puedes seguir explorando la app.", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(HospitalTheme.secondary)
            }
            Text("Accesos rápidos").font(.system(size: 16, weight: .semibold)).foregroundStyle(HospitalTheme.ink)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                PatientQuickAccessCard(icono: "calendar", titulo: "Mis citas") { navigate("appointments") }
                PatientQuickAccessCard(icono: "cross.case", titulo: "Solicitar atención") { navigate("request") }
                PatientQuickAccessCard(icono: "testtube.2", titulo: "Laboratorios") { navigate("laboratory") }
                PatientQuickAccessCard(icono: "pills", titulo: "Recetas") { navigate("prescriptions") }
            }
        }
    }
}

#Preview {
    ScrollView {
        PatientDashboardView(
            nombrePaciente: "",
            proximaCita: nil,
            navigate: { _ in }
        )
        .padding(.horizontal, 17)
        .padding(.top, 22)
    }
    .background(Color.fondoApp)
    .preferredColorScheme(.light)
}
