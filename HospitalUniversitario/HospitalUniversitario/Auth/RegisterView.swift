import SwiftUI

/// Pantalla de auto-registro de pacientes, conectada a Supabase.
///
/// Flujo real (reutiliza `public.submit_patient_registration`):
/// 1. `signUp(email:password:)` crea la cuenta de autenticación; el trigger
///    deja el perfil en estado `pending`. La confirmación de correo está
///    desactivada en el proyecto (decisión del usuario, 2026-10-31), por lo
///    que el signUp ya entrega una sesión usable.
/// 2. Si el signUp no devuelve sesión, se intenta iniciar sesión una vez como
///    respaldo antes de enviar la solicitud.
/// 3. Con la sesión y el perfil todavía `pending`, se envía la solicitud de
///    registro (DUI y teléfono incluidos) a la base de datos.
/// 4. El hospital revisa y aprueba la solicitud; recién entonces la cuenta se
///    activa y queda vinculada a un paciente.
///
/// Reglas de validación local, alineadas con el diccionario de datos:
/// - Nombres/Apellidos: `hospital.persons.given_names` / `family_names`
///   (text, obligatorios, 1–100 caracteres).
/// - Fecha de nacimiento: `persons.birth_date` (date, entre 1900-01-01 y hoy).
/// - Sexo administrativo: `persons.administrative_sex`
///   (`female` | `male` | `intersex` | `unknown`).
/// - DUI: formato salvadoreño `00000000-0` (8 dígitos + dígito verificador).
/// - Teléfono: `0000-0000` (8 dígitos).
/// - Correo y contraseña: los maneja Supabase Auth, fuera del diccionario.
struct RegisterView: View {
    let onBack: () -> Void
    @ObservedObject var store: HospitalStore

    @State private var givenNames = ""
    @State private var familyNames = ""
    @State private var dui = ""
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var sex = "female"
    @State private var phone = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    @State private var submitting = false
    @State private var errorMessage: String?
    @State private var submitted = false

    private let sexOptions: [(label: String, value: String)] = [
        ("Femenino", "female"), ("Masculino", "male"), ("Intersex", "intersex"), ("Desconocido", "unknown")
    ]

    init(store: HospitalStore, onBack: @escaping () -> Void) {
        self.store = store
        self.onBack = onBack
    }

    var body: some View {
        VStack(spacing: 0) {
            HospitalAuthHeader(title: "Crear cuenta", subtitle: "Completa tus datos para solicitar tu acceso.")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if submitted { successPanel }
                    else { formCard }
                }.padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - Formulario

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HospitalCard {
                VStack(alignment: .leading, spacing: 14) {
                    HospitalInputField(label: "Nombres", placeholder: "Tus nombres", text: $givenNames)
                    HospitalInputField(label: "Apellidos", placeholder: "Tus apellidos", text: $familyNames)
                    HospitalInputField(label: "DUI", placeholder: "00000000-0", text: $dui, keyboard: .numberPad)
                    DatePicker("Fecha de nacimiento", selection: $birthDate, in: Self.dateRange, displayedComponents: .date)
                        .font(.system(size: 13, weight: .semibold))
                        .environment(\.locale, Locale(identifier: "es_SV"))
                    sexPicker
                    HospitalInputField(label: "Teléfono", placeholder: "0000-0000", text: $phone, keyboard: .phonePad)
                    HospitalInputField(label: "Correo electrónico", placeholder: "nombre@correo.com", text: $email,
                                       keyboard: .emailAddress, contentType: .username, autocapitalization: .never)
                    HospitalSecureField(label: "Contraseña", placeholder: "Contraseña", text: $password,
                                         visible: $showPassword, contentType: .newPassword)
                    HospitalSecureField(label: "Confirmar contraseña", placeholder: "Repite tu contraseña",
                                         text: $confirmPassword, visible: $showConfirmPassword)
                }
            }.padding(.top, -28)
            HospitalNotice(text: "El hospital revisa y activa cada cuenta. Al enviar, crearás tu acceso y tu solicitud quedará en espera de aprobación.")
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
            Button { submit() } label: { Text(submitting ? "Enviando…" : "Registrarme") }
                .buttonStyle(HospitalPrimaryButtonStyle())
                .disabled(submitting || !requiredFieldsFilled)
            HStack(spacing: 4) {
                Text("¿Ya tienes cuenta?").font(.footnote).foregroundStyle(HospitalTheme.secondary)
                HospitalLink("Inicia sesión", action: onBack)
            }.frame(maxWidth: .infinity)
        }
        .onChange(of: dui) { _, value in
            let formatted = Self.formatDUI(value)
            if formatted != value { dui = formatted }
        }
        .onChange(of: phone) { _, value in
            let formatted = Self.formatPhone(value)
            if formatted != value { phone = formatted }
        }
    }

    private var sexPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sexo administrativo").font(.system(size: 13, weight: .semibold)).foregroundStyle(HospitalTheme.ink)
            Menu {
                ForEach(sexOptions, id: \.value) { option in
                    Button(option.label) { sex = option.value }
                }
            } label: {
                HStack {
                    Text(sexLabel).font(.system(size: 14)).foregroundStyle(HospitalTheme.ink)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 12)).foregroundStyle(HospitalTheme.secondary)
                }
                .padding(14)
                .background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Éxito

    private var successPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HospitalCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Solicitud enviada").font(.system(size: 17, weight: .semibold))
                    Text("Recibimos tu solicitud de registro. El hospital la revisará y, al aprobarla, activará tu cuenta y quedará vinculada a tu expediente.")
                        .font(.footnote).foregroundStyle(HospitalTheme.secondary)
                }
            }.padding(.top, -28)
            Button(action: onBack) { Text("Volver a iniciar sesión") }
                .buttonStyle(HospitalPrimaryButtonStyle())
        }
    }

    // MARK: - Lógica

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var sexLabel: String { sexOptions.first(where: { $0.value == sex })?.label ?? "Femenino" }

    private var birthDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: birthDate)
    }

    private var draft: RegistrationDraft {
        RegistrationDraft(facility: RegistrationDraft.centralFacility,
                          given: givenNames.trimmingCharacters(in: .whitespacesAndNewlines),
                          family: familyNames.trimmingCharacters(in: .whitespacesAndNewlines),
                          birthDate: birthDateString, sex: sex, dui: dui, phone: phone)
    }

    private static var dateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let minimum = calendar.date(from: DateComponents(year: 1900, month: 1, day: 1)) ?? .distantPast
        return minimum...Date()
    }

    /// Captura completa y dentro de límites. `nil` cuando todo es válido.
    private var validationError: String? {
        let names = givenNames.trimmingCharacters(in: .whitespacesAndNewlines)
        let surnames = familyNames.trimmingCharacters(in: .whitespacesAndNewlines)
        let duiDigits = dui.filter { $0.isNumber }
        let phoneDigits = phone.filter { $0.isNumber }

        if names.isEmpty || names.count > 100 { return "Introduce tus nombres (máximo 100 caracteres)." }
        if surnames.isEmpty || surnames.count > 100 { return "Introduce tus apellidos (máximo 100 caracteres)." }
        if duiDigits.count != 9 { return "El DUI debe contener 9 dígitos, por ejemplo 01234567-8." }
        if birthDate > Date() { return "La fecha de nacimiento no puede ser futura." }
        if birthDate < (Calendar.current.date(from: DateComponents(year: 1900, month: 1, day: 1)) ?? .distantPast) {
            return "La fecha de nacimiento debe ser igual o posterior a 1900."
        }
        if phoneDigits.count != 8 { return "El teléfono debe contener 8 dígitos, por ejemplo 7123-4567." }
        if trimmedEmail.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) == nil {
            return "Introduce un correo electrónico válido."
        }
        if password.count < 8 { return "La contraseña debe tener al menos 8 caracteres." }
        if confirmPassword != password { return "La confirmación de contraseña no coincide." }
        return nil
    }

    private var requiredFieldsFilled: Bool {
        ![givenNames, familyNames, dui, phone, email, password, confirmPassword]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { $0.isEmpty }
    }

    /// Crea la cuenta y envía la solicitud de registro en un solo paso. Si el
    /// signUp no entrega sesión, se intenta iniciar una vez como respaldo.
    private func submit() {
        guard validationError == nil else { return }
        submitting = true
        errorMessage = nil
        Task {
            defer { submitting = false }
            do {
                let hasSession = try await store.signUpForRegistration(email: trimmedEmail, password: password)
                if !hasSession {
                    try await store.signInForRegistration(email: trimmedEmail, password: password)
                }
                try await store.submitRegistration(draft)
                await store.endRegistrationSession()
                submitted = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Formato salvadoreño de 9 dígitos: 00000000-0.
    private static func formatDUI(_ value: String) -> String {
        let digits = String(value.filter { $0.isNumber }.prefix(9))
        guard digits.count > 8 else { return digits }
        return "\(digits.prefix(8))-\(digits.dropFirst(8))"
    }

    /// Formato telefónico de 8 dígitos: 0000-0000.
    private static func formatPhone(_ value: String) -> String {
        let digits = String(value.filter { $0.isNumber }.prefix(8))
        guard digits.count > 4 else { return digits }
        return "\(digits.prefix(4))-\(digits.dropFirst(4))"
    }
}

#Preview {
    RegisterView(store: HospitalStore(), onBack: {})
}
