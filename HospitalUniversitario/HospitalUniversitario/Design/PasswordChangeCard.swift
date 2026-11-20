import SwiftUI

/// Reglas del cambio de contraseña desde Perfil (paciente y médico). Espejo exacto de HospitalCore.validatePasswordChange
/// y HospitalCore.passwordChangeMessage (Shared/hospital-core.js): mínimo 8 como el registro, máximo 72 (bcrypt).
enum PasswordChangeRules {
    static func validate(current: String, new: String, confirm: String) -> String? {
        if current.isEmpty { return "Escribe tu contraseña actual." }
        if new.count < 8 { return "La nueva contraseña debe tener al menos 8 caracteres." }
        if new.count > 72 { return "La nueva contraseña admite como máximo 72 caracteres." }
        if new == current { return "La nueva contraseña debe ser distinta de la actual." }
        if confirm != new { return "La confirmación no coincide con la nueva contraseña." }
        return nil
    }
    /// Mensajes para los error_code de Supabase Auth al actualizar la contraseña.
    static func message(for code: String?) -> String {
        switch code {
        case "same_password": return "La nueva contraseña debe ser distinta de la actual."
        case "weak_password": return "Supabase rechazó la contraseña por ser poco segura. Combina letras, números y símbolos."
        case "reauthentication_needed", "reauthentication_not_valid": return "Por seguridad debes volver a iniciar sesión antes de cambiar la contraseña."
        case "over_request_rate_limit": return "Demasiados intentos. Espera unos minutos e inténtalo de nuevo."
        default: return "No se pudo cambiar la contraseña. Inténtalo de nuevo."
        }
    }
}

/// Tarjeta «Seguridad» del Perfil (paciente y médico; paridad con passwordCard de web-preview/app.js).
/// La contraseña se actualiza en Supabase Auth tras verificar la actual; los campos se vacían al terminar.
struct PasswordChangeCard: View {
    let change: (String, String) async throws -> Void
    @State private var current = ""
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var visible = false
    @State private var saving = false
    @State private var error: String?
    @State private var success: String?

    private var problem: String? { PasswordChangeRules.validate(current: current, new: newPassword, confirm: confirm) }
    private var touched: Bool { !current.isEmpty || !newPassword.isEmpty || !confirm.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "lock.rotation").font(.headline).foregroundStyle(HospitalTheme.wine)
                    .frame(width: 40, height: 40).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Seguridad").font(.headline).foregroundStyle(HospitalTheme.ink)
                    Text("Cambia la contraseña con la que inicias sesión.").font(.caption).foregroundStyle(HospitalTheme.secondary)
                }
            }
            field("Contraseña actual", text: $current, content: .password)
            field("Nueva contraseña", text: $newPassword, content: .newPassword)
            field("Confirmar nueva contraseña", text: $confirm, content: .newPassword)
            Toggle("Mostrar contraseñas", isOn: $visible).font(.footnote).tint(HospitalTheme.wine)
            Label("Mínimo 8 caracteres y distinta de la actual.", systemImage: "info.circle").font(.caption).foregroundStyle(HospitalTheme.secondary)
            if touched, let problem {
                Text(problem).font(.footnote.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote.weight(.semibold)).foregroundStyle(Color(red: 0.63, green: 0.07, blue: 0.18))
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 0.99, green: 0.93, blue: 0.93), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if let success {
                Label(success, systemImage: "checkmark.circle.fill").font(.footnote.weight(.semibold)).foregroundStyle(Color(red: 0.12, green: 0.42, blue: 0.24))
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 0.91, green: 0.96, blue: 0.93), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Button {
                Task { await submit() }
            } label: {
                HStack(spacing: 8) {
                    if saving { ProgressView().tint(.white) } else { Image(systemName: "checkmark.shield.fill") }
                    Text(saving ? "Actualizando…" : "Actualizar contraseña").font(.headline)
                }.foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 50)
                    .background(LinearGradient.vinoDestacado, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .opacity(problem == nil && !saving ? 1 : 0.55)
            }.buttonStyle(.plain).disabled(problem != nil || saving)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(HospitalTheme.rose, lineWidth: 1))
        .onDisappear { current = ""; newPassword = ""; confirm = "" }
    }

    private func field(_ label: String, text: Binding<String>, content: UITextContentType) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(HospitalTheme.ink)
            Group {
                if visible { TextField(label, text: text) } else { SecureField(label, text: text) }
            }
            .textContentType(content).textInputAutocapitalization(.never).autocorrectionDisabled()
            .padding(12).background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel(label)
        }
    }

    private func submit() async {
        guard problem == nil, !saving else { return }
        saving = true; error = nil; success = nil
        defer { saving = false }
        do {
            try await change(current, newPassword)
            current = ""; newPassword = ""; confirm = ""
            success = "Contraseña actualizada. Úsala la próxima vez que inicies sesión."
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "No se pudo cambiar la contraseña. Inténtalo de nuevo."
        }
    }
}
