import SwiftUI

/// Card de saludo con iniciales del paciente y mensaje de bienvenida.
struct PatientGreetingCard: View {
    let nombre: String
    let iniciales: String

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hola, \(nombre) 👋").font(.system(size: 22, weight: .bold)).foregroundStyle(HospitalTheme.ink)
                Text("Aquí está el resumen de tu día.").font(.system(size: 12)).foregroundStyle(HospitalTheme.secondary)
            }
            Spacer(minLength: 8)
            Text(iniciales)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.vinoPrincipal)
                .frame(width: 58, height: 58)
                .background(HospitalTheme.rose, in: Circle())
                .overlay(Circle().stroke(Color.rojoAcento.opacity(0.25), lineWidth: 2))
                .accessibilityLabel("Foto de perfil de \(nombre)")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fondoCard, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: HospitalTheme.ink.opacity(0.06), radius: 10, y: 4)
    }
}

/// Card destacada con la fecha de hoy y, si existe, la próxima cita del paciente.
struct PatientDateAppointmentCard: View {
    let proximaCita: ProximaCita?

    /// Fecha de hoy en español: día de la semana, número y mes.
    private var fechaHoy: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_SV")
        formatter.dateFormat = "EEEE d 'de' MMMM"
        return formatter.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "calendar").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                VStack(alignment: .leading, spacing: 2) {
                    Text("HOY").font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(.white.opacity(0.8))
                    Text(fechaHoy).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                }
            }
            Rectangle().fill(.white.opacity(0.25)).frame(height: 1)
            Text("PRÓXIMA CITA").font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(.white.opacity(0.8))
            if let cita = proximaCita {
                Text(cita.dia).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.95))
                Text(cita.hora).font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
                HStack(spacing: 6) {
                    Image(systemName: "stethoscope").font(.system(size: 12))
                    Text(cita.medico).font(.system(size: 12))
                }.foregroundStyle(.white.opacity(0.9))
            } else {
                Text("No tienes citas programadas.").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Text("Agenda una desde el acceso «Agendar cita».").font(.system(size: 11)).foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.vinoDestacado, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.vinoPrincipal.opacity(0.25), radius: 12, y: 6)
    }
}

/// Card de acceso rápido con icono, etiqueta y estado visual al presionar.
struct PatientQuickAccessCard: View {
    let icono: String
    let titulo: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    Circle().fill(HospitalTheme.rose).frame(width: 40, height: 40)
                    Image(systemName: icono).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.vinoPrincipal)
                }
                Text(titulo)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HospitalTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .padding(14)
            .background(Color.fondoCard, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.rojoAcento.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(PatientQuickAccessStyle())
        .accessibilityLabel(titulo)
    }
}

/// Estado visual de las cards de acceso rápido: escala y atenuación al tocar.
private struct PatientQuickAccessStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
