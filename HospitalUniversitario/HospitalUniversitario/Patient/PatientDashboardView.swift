import SwiftUI

/// Modelo de presentación de la próxima cita.
/// Los datos reales llegarán con el modelo de citas del paciente.
struct ProximaCita: Identifiable, Equatable {
    let id = UUID()
    let dia: String
    let hora: String
    let medico: String
}

/// Dashboard principal del paciente: saludo, card de fecha con próxima cita
/// y accesos rápidos. Se integra dentro de la portal existente, respetando su
/// encabezado y la barra de navegación inferior del rol.
struct PatientDashboardView: View {
    /// Nombre y apellido del paciente; se parametriza hasta existir el modelo real.
    var nombrePaciente: String = "Gaby Diaz"
    /// Próxima cita del paciente, si existe.
    var proximaCita: ProximaCita?
    /// Navegación hacia los destinos del catálogo (mismo sistema que el resto de la app).
    var navigate: (String) -> Void

    /// Iniciales del nombre para el avatar (por ejemplo, «Gaby Diaz» → «GD»).
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
            PatientDateAppointmentCard(proximaCita: proximaCita)
            Text("Accesos rápidos").font(.system(size: 16, weight: .semibold)).foregroundStyle(HospitalTheme.ink)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                PatientQuickAccessCard(icono: "calendar", titulo: "Mis citas") { navigate("appointments") }
                PatientQuickAccessCard(icono: "testtube.2", titulo: "Laboratorios") { navigate("laboratory") }
                PatientQuickAccessCard(icono: "doc.text", titulo: "Expedientes") { navigate("chart") }
                PatientQuickAccessCard(icono: "pills", titulo: "Recetas") { navigate("prescriptions") }
            }
        }
    }
}

#Preview {
    ScrollView {
        PatientDashboardView(
            nombrePaciente: "Gaby Diaz",
            proximaCita: ProximaCita(
                dia: "Viernes 30 de octubre",
                hora: "11:00 am",
                medico: "Dra. Ana Morales · Medicina interna"
            ),
            navigate: { _ in }
        )
        .padding(.horizontal, 17)
        .padding(.top, 22)
    }
    .background(Color.fondoApp)
    .preferredColorScheme(.light)
}
