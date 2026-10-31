import SwiftUI

/// Pantalla de registro con los campos solicitados por el usuario.
///
/// Esta pantalla es de presentación: valida los formatos en el cliente y
/// muestra un aviso al completar el formulario, pero **no envía datos a la
/// base de datos ni llama a Supabase**. En el modelo real del hospital, las
/// cuentas son creadas, activadas y vinculadas por personal administrativo;
/// el trigger de perfiles deja cualquier cuenta nueva en estado `pending`.
///
/// Reglas de validación local, alineadas con el diccionario de datos:
/// - Nombres/Apellidos: `hospital.persons.given_names` / `family_names`
///   (text, obligatorios, 1–100 caracteres).
/// - Edad: el esquema no almacena edad, guarda `persons.birth_date`; aquí se
///   captura como número entero de 1 a 120 años (decisión del usuario).
/// - DUI: no existe columna de DUI en el diccionario; se captura con el
///   formato salvadoreño de 9 dígitos `0000-00000` (decisión del usuario).
/// - Teléfono: misma expresión regular que `MobileModuleViewModel.savePhone`
///   para `update_my_phone` en `hospital.person_contacts`.
/// - Correo y contraseña: los maneja Supabase Auth, fuera del diccionario.
struct RegisterView: View {
    let onBack: () -> Void

    @State private var givenNames = ""
    @State private var familyNames = ""
    @State private var dui = ""
    @State private var age = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    @State private var submitted = false
    @State private var notice: String?

    init(onBack: @escaping () -> Void) { self.onBack = onBack }

    var body: some View {
        VStack(spacing: 0) {
            HospitalAuthHeader(title: "Crear cuenta", subtitle: "Completa tus datos para solicitar tu acceso.")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HospitalCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HospitalInputField(label: "Nombres", placeholder: "Tus nombres", text: $givenNames)
                            HospitalInputField(label: "Apellidos", placeholder: "Tus apellidos", text: $familyNames)
                            HospitalInputField(label: "DUI", placeholder: "0000-00000", text: $dui, keyboard: .numberPad)
                            HospitalInputField(label: "Edad", placeholder: "Ejemplo: 34", text: $age, keyboard: .numberPad)
                            HospitalInputField(label: "Teléfono", placeholder: "0000-0000", text: $phone, keyboard: .phonePad)
                            HospitalInputField(label: "Correo electrónico", placeholder: "nombre@correo.com", text: $email,
                                               keyboard: .emailAddress, contentType: .username, autocapitalization: .never)
                            HospitalSecureField(label: "Contraseña", placeholder: "Contraseña", text: $password,
                                                 visible: $showPassword, contentType: .newPassword)
                            HospitalSecureField(label: "Confirmar contraseña", placeholder: "Repite tu contraseña",
                                                 text: $confirmPassword, visible: $showConfirmPassword)
                        }
                    }.padding(.top, -28)
                    HospitalNotice(text: "El hospital crea y activa cada cuenta; recibirás la confirmación en tu correo electrónico.")
                    if submitted, let error = validationError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                    if let notice {
                        HospitalNotice(text: notice)
                    }
                    Button { submit() } label: { Text("Registrarme") }
                        .buttonStyle(HospitalPrimaryButtonStyle())
                        .disabled(!requiredFieldsFilled)
                    HStack(spacing: 4) {
                        Text("¿Ya tienes cuenta?").font(.footnote).foregroundStyle(HospitalTheme.secondary)
                        HospitalLink("Inicia sesión", action: onBack)
                    }.frame(maxWidth: .infinity)
                }.padding(.horizontal, 16).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onChange(of: dui) { _, value in
            let formatted = Self.formatDUI(value)
            if formatted != value { dui = formatted }
        }
        .onChange(of: age) { _, value in
            let filtered = String(value.filter { $0.isNumber }.prefix(3))
            if filtered != value { age = filtered }
        }
    }

    /// Captura completa y dentro de límites. `nil` cuando todo es válido.
    private var validationError: String? {
        let names = givenNames.trimmingCharacters(in: .whitespacesAndNewlines)
        let surnames = familyNames.trimmingCharacters(in: .whitespacesAndNewlines)
        let duiDigits = dui.filter { $0.isNumber }
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let phoneValue = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let ageValue = Int(age)

        if names.isEmpty || names.count > 100 { return "Introduce tus nombres (máximo 100 caracteres)." }
        if surnames.isEmpty || surnames.count > 100 { return "Introduce tus apellidos (máximo 100 caracteres)." }
        if duiDigits.count != 9 { return "El DUI debe contener 9 dígitos, por ejemplo 0123-45678." }
        guard let ageValue, (1...120).contains(ageValue) else { return "Introduce una edad entre 1 y 120 años." }
        if phoneValue.range(of: "^[+]?[0-9() -]{7,25}$", options: .regularExpression) == nil {
            return "Introduce un teléfono válido."
        }
        if mail.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) == nil {
            return "Introduce un correo electrónico válido."
        }
        if password.count < 8 { return "La contraseña debe tener al menos 8 caracteres." }
        if confirmPassword != password { return "La confirmación de contraseña no coincide." }
        return nil
    }

    private var requiredFieldsFilled: Bool {
        ![givenNames, familyNames, dui, age, phone, email, password, confirmPassword]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { $0.isEmpty }
    }

    /// Solo presentación: no crea usuarios ni escribe en la base de datos.
    private func submit() {
        submitted = true
        notice = nil
        guard validationError == nil else { return }
        notice = "Formulario de demostración: no se envía a la base de datos. El hospital creará y activará tu cuenta."
    }

    /// Formato salvadoreño de 9 dígitos: 0000-00000.
    private static func formatDUI(_ value: String) -> String {
        let digits = String(value.filter { $0.isNumber }.prefix(9))
        guard digits.count > 4 else { return digits }
        return "\(digits.prefix(4))-\(digits.dropFirst(4))"
    }
}

#Preview {
    RegisterView(onBack: {})
}
