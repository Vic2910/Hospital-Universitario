import Testing
@testable import HospitalUniversitario

/// Misma regla que HospitalCore.validatePasswordChange y HospitalCore.passwordChangeMessage (hospital-core.js).
struct PasswordChangeTests {
    @Test func validationMatchesTheSharedRule() {
        #expect(PasswordChangeRules.validate(current: "", new: "NuevaClave2026", confirm: "NuevaClave2026") == "Escribe tu contraseña actual.")
        #expect(PasswordChangeRules.validate(current: "actual-123", new: "corta", confirm: "corta") == "La nueva contraseña debe tener al menos 8 caracteres.")
        #expect(PasswordChangeRules.validate(current: "actual-123", new: String(repeating: "a", count: 73), confirm: String(repeating: "a", count: 73)) == "La nueva contraseña admite como máximo 72 caracteres.")
        #expect(PasswordChangeRules.validate(current: "actual-123", new: "actual-123", confirm: "actual-123") == "La nueva contraseña debe ser distinta de la actual.")
        #expect(PasswordChangeRules.validate(current: "actual-123", new: "NuevaClave2026", confirm: "Otra2026") == "La confirmación no coincide con la nueva contraseña.")
        #expect(PasswordChangeRules.validate(current: "actual-123", new: "NuevaClave2026", confirm: "NuevaClave2026") == nil)
    }

    @Test func supabaseAuthCodesHaveClearMessages() {
        #expect(PasswordChangeRules.message(for: "same_password") == "La nueva contraseña debe ser distinta de la actual.")
        #expect(PasswordChangeRules.message(for: "weak_password").contains("poco segura"))
        #expect(PasswordChangeRules.message(for: nil) == "No se pudo cambiar la contraseña. Inténtalo de nuevo.")
    }
}
