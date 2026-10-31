import SwiftUI

/// Card blanca de sección con título e icono, usada en el formulario de citas.
struct PatientFormCard<Content: View>: View {
    let titulo: String
    let icono: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icono).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.vinoPrincipal)
                Text(titulo).font(.system(size: 15, weight: .semibold)).foregroundStyle(HospitalTheme.ink)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fondoCard, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: HospitalTheme.ink.opacity(0.05), radius: 8, y: 3)
    }
}

/// Chip seleccionable con animación suave; se usa para síntomas y especialidades.
struct PatientSelectChip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let texto: String
    let seleccionado: Bool
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Label(texto, systemImage: seleccionado ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12, weight: seleccionado ? .semibold : .medium))
                .foregroundStyle(seleccionado ? .white : HospitalTheme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(seleccionado ? Color.vinoPrincipal : Color.fondoCard, in: Capsule())
                .overlay(Capsule().stroke(seleccionado ? Color.clear : Color.rojoAcento.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(PatientChipPressStyle())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: seleccionado)
        .accessibilityAddTraits(seleccionado ? .isSelected : [])
    }
}

/// Chip de horario con día y franja horaria; se usa al elegir especialidad.
struct PatientSlotChip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let dia: String
    let hora: String
    let seleccionado: Bool
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            VStack(spacing: 3) {
                if seleccionado { Image(systemName: "checkmark.circle.fill") }
                Text(dia.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.8)
                Text(hora).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(seleccionado ? .white : HospitalTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(
                seleccionado ? AnyShapeStyle(LinearGradient.vinoDestacado) : AnyShapeStyle(Color.fondoCard),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(seleccionado ? Color.clear : Color.rojoAcento.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(PatientChipPressStyle())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: seleccionado)
        .accessibilityAddTraits(seleccionado ? .isSelected : [])
    }
}

/// Card de confirmación animada al preparar la cita.
struct PatientScheduleSuccess: View {
    let especialidad: String
    let horario: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 26)).foregroundStyle(Color.rojoAcento)
            VStack(alignment: .leading, spacing: 4) {
                Text("Solicitud Pendiente").font(.system(size: 15, weight: .semibold)).foregroundStyle(HospitalTheme.ink)
                Text("\(especialidad) · \(horario)").font(.system(size: 12)).foregroundStyle(HospitalTheme.secondary)
                Text("Solicitud de ejemplo guardada como Pendiente. Recepción debe asignar una cita; no se envió al hospital.")
                    .font(.system(size: 11)).foregroundStyle(HospitalTheme.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

/// Estado de presión compartido por los chips de la pantalla de citas.
private struct PatientChipPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Selección excluyente de turno, manteniendo los valores Mañana/Tarde del modelo.
struct PatientTimePreferenceCard: View {
    let title: String
    let period: String
    let icon: String
    let selected: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon).font(.system(size: 21))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 18))
                }
                Text(title).font(.system(size: 16, weight: .bold))
                Text(period + (period == "AM" ? " · Antes del mediodía" : " · Después del mediodía")).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            }.foregroundStyle(selected ? HospitalTheme.wine : HospitalTheme.secondary)
                .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading).padding(14)
                .background(selected ? HospitalTheme.rose : HospitalTheme.background, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? HospitalTheme.wine : HospitalTheme.rose, lineWidth: selected ? 2 : 1))
        }.buttonStyle(.plain).accessibilityLabel(title + " · " + period).accessibilityValue(selected ? "Seleccionado" : "Sin seleccionar")
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: selected)
    }
}
