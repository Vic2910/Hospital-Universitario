import SwiftUI

enum ApplicantTab: Hashable { case home, request, requests }

/// Vista de diseño del solicitante sin expediente. Datos de ejemplo locales:
/// no consulta Supabase, no crea citas y no concede acceso a datos reales.
@MainActor
struct ApplicantDemoView: View {
    @StateObject private var store = ApplicantDemoStore()
    @State private var tab: ApplicantTab = .home
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HospitalAuthHeader(title: title, subtitle: "Vista de diseño con datos de ejemplo locales.")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HospitalNotice(text: "Vista de diseño: nada se envía al hospital ni a Supabase. Una solicitud no es una cita.")
                    if store.person == nil {
                        ApplicantCompleteDataView(store: store)
                        Button("Salir de la demostración", action: onExit)
                            .font(.footnote)
                    } else {
                        content
                        if let notice = store.notice { HospitalNotice(text: notice) }
                        navigation
                    }
                }.padding(.horizontal, 16).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(HospitalTheme.background)
    }

    private var title: String {
        guard store.person != nil else { return "Completa tus datos" }
        switch tab {
        case .home: return "Inicio"
        case .request: return "Solicitar atención"
        case .requests: return "Mis solicitudes"
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .home: ApplicantHomeView(store: store, openRequest: { tab = .request }, openRequests: { tab = .requests })
        case .request: ApplicantRequestFormView(store: store, onSent: { tab = .requests })
        case .requests: ApplicantRequestsView(store: store)
        }
    }

    private var navigation: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                navButton("Inicio", .home)
                navButton("Solicitar", .request)
                navButton("Mis solicitudes", .requests)
            }
            Button("Salir de la demostración", action: onExit)
                .font(.footnote)
                .foregroundStyle(HospitalTheme.secondary)
        }
    }

    private func navButton(_ label: String, _ destination: ApplicantTab) -> some View {
        Button { tab = destination } label: {
            Text(label)
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(tab == destination ? Color.white : HospitalTheme.wine)
                .background(tab == destination ? HospitalTheme.wine : Color.white, in: RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityAddTraits(tab == destination ? .isSelected : [])
    }
}

/// Datos personales: nombres, apellidos, DUI, fecha de nacimiento y teléfono.
struct ApplicantCompleteDataView: View {
    @ObservedObject var store: ApplicantDemoStore
    @State private var givenNames = ""
    @State private var familyNames = ""
    @State private var dui = ""
    @State private var birthDate = Date()
    @State private var birthDateChosen = false
    @State private var phone = ""
    @State private var problem: String?

    var body: some View {
        HospitalCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tu cuenta no tiene expediente clínico. Estos datos sirven para verificar tu identidad en recepción.")
                    .font(.footnote).foregroundStyle(HospitalTheme.secondary)
                HospitalInputField(label: "Nombres", placeholder: "Tus nombres", text: $givenNames)
                HospitalInputField(label: "Apellidos", placeholder: "Tus apellidos", text: $familyNames)
                HospitalInputField(label: "DUI", placeholder: "0000-00000", text: $dui, keyboard: .numberPad)
                    .onChange(of: dui) { _, value in
                        let formatted = store.rules.formatDUI(value)
                        if formatted != value { dui = formatted }
                    }
                birthDateField
                HospitalInputField(label: "Teléfono", placeholder: "0000-0000", text: $phone, keyboard: .phonePad)
                if let problem {
                    Text(problem).font(.footnote).foregroundStyle(.red)
                }
                Button { save() } label: { Text("Guardar datos") }
                    .buttonStyle(HospitalPrimaryButtonStyle())
            }
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

    private func save() {
        problem = store.savePersonal(ApplicantPersonalData(
            given: givenNames, family: familyNames, dui: dui,
            birthDate: birthDateChosen ? birthDate : nil, phone: phone))
    }
}

struct ApplicantHomeView: View {
    @ObservedObject var store: ApplicantDemoStore
    let openRequest: () -> Void
    let openRequests: () -> Void

    var body: some View {
        HospitalCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Hola, \(store.person?.given.components(separatedBy: " ").first ?? "Solicitante")")
                    .font(.title3.weight(.bold))
                Text("Todavía no tienes expediente. Puedes solicitar atención y recepción la revisará.")
                    .font(.footnote).foregroundStyle(HospitalTheme.secondary)
                Text("Solicitudes registradas en esta vista: \(store.requests.count)")
                    .font(.footnote).foregroundStyle(HospitalTheme.secondary)
                Button { openRequest() } label: { Text("Solicitar atención") }
                    .buttonStyle(HospitalPrimaryButtonStyle())
                Button("Ver mis solicitudes", action: openRequests)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HospitalTheme.wine)
            }
        }
    }
}

struct ApplicantRequestFormView: View {
    @ObservedObject var store: ApplicantDemoStore
    let onSent: () -> Void
    @State private var draft = ApplicantRequestDraft()
    @State private var problem: String?

    var body: some View {
        HospitalCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Recepción confirmará disponibilidad. Esta solicitud no reserva ninguna cita.")
                    .font(.footnote).foregroundStyle(HospitalTheme.secondary)
                Text("Especialidad").font(.subheadline.weight(.semibold))
                Picker("Especialidad", selection: $draft.specialty) {
                    Text("Elige una especialidad").tag("")
                    ForEach(store.rules.specialties, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                Text("Motivo de la consulta").font(.subheadline.weight(.semibold))
                TextField("Describe tu motivo", text: $draft.reason, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                DatePicker("Fecha preferida", selection: $draft.date, in: Date()..., displayedComponents: .date)
                Text("Preferencia de horario").font(.subheadline.weight(.semibold))
                HStack(spacing: 10) {
                    periodButton("morning")
                    periodButton("afternoon")
                }
                if let problem {
                    Text(problem).font(.footnote).foregroundStyle(.red)
                }
                Button { submit() } label: { Text("Solicitar atención") }
                    .buttonStyle(HospitalPrimaryButtonStyle())
            }
        }
    }

    private func periodButton(_ key: String) -> some View {
        let selected = draft.period == key
        return Button { draft.period = key } label: {
            Text(store.rules.periodLabel(key))
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(selected ? HospitalTheme.wine : HospitalTheme.ink)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? HospitalTheme.wine : HospitalTheme.secondary.opacity(0.3), lineWidth: selected ? 2 : 1))
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func submit() {
        problem = store.submitRequest(draft)
        if problem == nil {
            draft = ApplicantRequestDraft()
            onSent()
        }
    }
}

struct ApplicantRequestsView: View {
    @ObservedObject var store: ApplicantDemoStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Registros de ejemplo locales. Ninguno es una cita ni se envía al hospital.")
                .font(.footnote).foregroundStyle(HospitalTheme.secondary)
            if store.requests.isEmpty {
                HospitalCard {
                    Text("Aún no tienes solicitudes en esta vista.")
                        .font(.footnote).foregroundStyle(HospitalTheme.secondary)
                }
            }
            ForEach(store.requests) { request in
                ApplicantRequestCard(store: store, request: request)
            }
            Button("Mostrar ejemplos de rechazada y cancelada") { store.addStateExamples() }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(HospitalTheme.wine)
        }
    }
}

struct ApplicantRequestCard: View {
    @ObservedObject var store: ApplicantDemoStore
    let request: ApplicantRequestRecord

    var body: some View {
        let state = store.rules.stateView(status: request.status, appointmentStatus: request.appointmentStatus)
        HospitalCard {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(request.specialty).font(.headline)
                    HospitalBadge(text: state.label, warning: state.key == "pending" || state.key == "review")
                }
                Text(request.reason).font(.subheadline)
                Text("Preferencia: \(request.date.formatted(date: .abbreviated, time: .omitted)) · \(store.rules.periodLabel(request.period))")
                    .font(.footnote).foregroundStyle(HospitalTheme.secondary)
                if let reason = request.decisionReason {
                    Text("Motivo: \(reason)").font(.footnote).foregroundStyle(HospitalTheme.secondary)
                }
                if state.key == "scheduled" {
                    Text("Cita de ejemplo: la programa recepción en el sistema real.")
                        .font(.footnote).foregroundStyle(HospitalTheme.secondary)
                }
                Text("Solicitud de ejemplo · no es una cita")
                    .font(.caption).foregroundStyle(HospitalTheme.secondary)
                if ApplicantDemoStore.canAdvance(request) {
                    Button("Simular avance de recepción (ejemplo)") { store.advance(request.id) }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(HospitalTheme.wine)
                }
            }
        }
    }
}

#Preview("Solicitante · datos de ejemplo") {
    ApplicantDemoView(onExit: {})
}
