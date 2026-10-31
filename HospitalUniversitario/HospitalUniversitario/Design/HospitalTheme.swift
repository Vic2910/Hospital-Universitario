import SwiftUI

enum HospitalTheme {
    static let wine = Color(red: 119/255, green: 7/255, blue: 39/255)
    static let background = Color(red: 248/255, green: 248/255, blue: 250/255)
    static let ink = Color(red: 36/255, green: 41/255, blue: 54/255)
    static let secondary = Color(red: 117/255, green: 126/255, blue: 145/255)
    static let rose = Color(red: 251/255, green: 234/255, blue: 240/255)
    static let green = Color(red: 227/255, green: 246/255, blue: 234/255)
}

struct HospitalCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct HospitalBadge: View {
    let text: String
    var warning = false
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 5).frame(minWidth: 100, alignment: .leading)
            .background(warning ? Color(red: 1, green: 0.95, blue: 0.85) : HospitalTheme.green, in: Capsule())
    }
}

enum HospitalLabels {
    static func status(_ value: String) -> String {
        ["pending":"Pendiente", "confirmed":"Confirmado", "cancelled":"Cancelado", "waiting":"En espera", "called":"Llamado", "in_service":"En atención", "completed":"Finalizado"][value] ?? value
    }
}

// MARK: - Componentes de autenticación (login/registro)

/// Encabezado vino con esquina inferior derecha redondeada, según las referencias.
struct HospitalAuthHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "cross.case.fill").font(.system(size: 15))
                Text("Hospital Universitario").font(.system(size: 14, weight: .medium))
                Spacer()
            }.padding(.bottom, 20)
            Text(title).font(.system(size: 28, weight: .semibold))
            Text(subtitle).font(.system(size: 12)).opacity(0.9).padding(.top, 8)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 46)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HospitalTheme.wine, in: RoundedRectangle(cornerRadius: 0))
        .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 28))
        .background(HospitalTheme.wine.ignoresSafeArea(edges: .top))
    }
}

/// Campo de texto con etiqueta superior y fondo gris claro, dentro de tarjetas blancas.
struct HospitalInputField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    var autocapitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(HospitalTheme.ink)
            TextField(placeholder, text: $text)
                .font(.system(size: 14))
                .keyboardType(keyboard)
                .textContentType(contentType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
                .padding(14)
                .background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// Campo de contraseña con icono para mostrar u ocultar el contenido.
struct HospitalSecureField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    @Binding var visible: Bool
    var contentType: UITextContentType?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(HospitalTheme.ink)
            HStack {
                Group {
                    if visible { TextField(placeholder, text: $text) }
                    else { SecureField(placeholder, text: $text) }
                }
                .font(.system(size: 14))
                .textContentType(contentType)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                Button { visible.toggle() } label: {
                    Image(systemName: visible ? "eye.slash" : "eye").foregroundStyle(HospitalTheme.secondary)
                }
                .accessibilityLabel(visible ? "Ocultar contraseña" : "Mostrar contraseña")
            }
            .padding(14)
            .background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// Botón principal vino de ancho completo, como el de las referencias.
struct HospitalPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(HospitalTheme.wine, in: RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
    }
}

/// Aviso en franja rosa, como el de las pantallas de formulario de referencia.
struct HospitalNotice: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(HospitalTheme.wine)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Enlace de texto (no botón relleno) para acciones secundarias del login.
struct HospitalLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
        }
        .buttonStyle(.plain)
    }
}
