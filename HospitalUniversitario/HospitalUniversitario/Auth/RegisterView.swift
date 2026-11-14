import SwiftUI

/// Crea únicamente la cuenta de acceso; recepción gestiona paciente, expediente y citas.
@MainActor
struct RegisterView: View {
    @ObservedObject var store: HospitalStore
    let onBack: () -> Void
    var onContinueDemo: (() -> Void)? = nil

    @State private var givenNames = ""
    @State private var familyNames = ""
    @State private var dui = ""
    @State private var birthDate = Date()
    @State private var birthDateChosen = false
    @State private var city = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    @State private var submitted = false

    private var rules: ApplicantRules { ApplicantRules.shared }

    init(store: HospitalStore, onBack: @escaping () -> Void, onContinueDemo: (() -> Void)? = nil) {
        self.store = store
        self.onBack = onBack
        self.onContinueDemo = onContinueDemo
    }

    var body: some View {
        VStack(spacing: 0) {
            HospitalAuthHeader(title: "Crear cuenta", subtitle: "Completa tus datos para solicitar atención.")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HospitalCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HospitalInputField(label: "Nombres", placeholder: "Tus nombres", text: $givenNames)
                            HospitalInputField(label: "Apellidos", placeholder: "Tus apellidos", text: $familyNames)
                            birthDateField
                            HospitalInputField(label: "DUI", placeholder: "00000000-0", text: $dui, keyboard: .numberPad)
                            HospitalInputField(label: "Teléfono", placeholder: "0000-0000", text: $phone, keyboard: .phonePad)
                            HospitalInputField(label: "Ciudad (opcional)", placeholder: "Tu ciudad", text: $city)
                            HospitalInputField(label: "Correo electrónico", placeholder: "nombre@correo.com", text: $email,
                                               keyboard: .emailAddress, contentType: .username, autocapitalization: .never)
                            HospitalSecureField(label: "Contraseña", placeholder: "Contraseña", text: $password,
                                                 visible: $showPassword, contentType: .newPassword)
                            HospitalSecureField(label: "Confirmar contraseña", placeholder: "Repite tu contraseña",
                                                 text: $confirmPassword, visible: $showConfirmPassword)
                        }
                    }.padding(.top, -28)
                    HospitalNotice(text: "El registro crea únicamente tu cuenta de la app. Recepción gestiona tu expediente y programa tus citas.")
                    HospitalNotice(text: "Si ya tienes expediente de atención presencial, utiliza tu mismo DUI. No se creará otro expediente: recepción debe verificar tu identidad y confirmar la vinculación. Cualquier asociación existente requiere revisión en recepción.")
                    if submitted, let error = validationError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                    if let onContinueDemo {
                        Button("Explorar demostración sin crear cuenta", action: onContinueDemo)
                            .buttonStyle(HospitalPrimaryButtonStyle())
                    }
                    Button { Task { await submit() } } label: { Text("Registrarme") }
                        .buttonStyle(HospitalPrimaryButtonStyle())
                        .disabled(!requiredFieldsFilled || store.busy)
                    HStack(spacing: 4) {
                        Text("¿Ya tienes cuenta?").font(.footnote).foregroundStyle(HospitalTheme.secondary)
                        HospitalLink("Inicia sesión", action: onBack)
                    }.frame(maxWidth: .infinity)
                }.padding(.horizontal, 16).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onChange(of: dui) { _, value in
            let formatted = rules.formatDUI(value)
            if formatted != value { dui = formatted }
        }
    }

    @ViewBuilder private var birthDateField: some View {
        if birthDateChosen {
            DatePicker("Fecha de nacimiento", selection: $birthDate, in: ...Date(), displayedComponents: .date)
        } else {
            Button("Elegir fecha de nacimiento") {
                birthDate = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
                birthDateChosen = true
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(HospitalTheme.wine)
        }
    }

    private var personalData: ApplicantPersonalData {
        ApplicantPersonalData(given: givenNames, family: familyNames, dui: dui,
                              birthDate: birthDateChosen ? birthDate : nil, phone: phone)
    }

    /// Primer problema encontrado, o nil cuando todo es válido.
    private var validationError: String? {
        return rules.validateAccount(personalData, email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                              password: password, confirm: confirmPassword)
    }

    private var requiredFieldsFilled: Bool {
        birthDateChosen && ![givenNames, familyNames, dui, phone, email, password, confirmPassword]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { $0.isEmpty }
    }

    private func submit() async {
        submitted = true
        guard validationError == nil else { return }
        await store.register(email: email, password: password, values: [
            "first_name": givenNames.trimmingCharacters(in: .whitespacesAndNewlines),
            "last_name": familyNames.trimmingCharacters(in: .whitespacesAndNewlines),
            "birth_date": ApplicantRules.isoDay(birthDate), "city": city.trimmingCharacters(in: .whitespacesAndNewlines),
            "dui": rules.formatDUI(dui), "phone": phone.trimmingCharacters(in: .whitespacesAndNewlines)
        ])
        password = ""; confirmPassword = ""
    }
}

#Preview {
    RegisterView(store: HospitalStore(), onBack: {})
}
