import SwiftUI

@MainActor
struct ContentView: View {
    @StateObject private var store = HospitalStore()
    @StateObject private var appointmentFlow = PatientAppointmentFlowStore()
    @StateObject private var labDesign = ClinicalLabDesignStore()
    @State private var showLabDesign = false
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var showRegister = false
    @State private var showApplicantDemo = false
    @State private var showRecoveryInfo = false
    @State private var search = ""
    @State private var notificationsPresented = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            if store.access == nil {
                if showApplicantDemo { ApplicantDemoView(onExit: { showApplicantDemo = false }) }
                else if showRegister {
                    RegisterView(store: store, onBack: { showRegister = false }, onContinueDemo: {
                        showRegister = false
                        showApplicantDemo = true
                    })
                }
                else { login }
            }
            else if store.selectedRole == nil { rolePicker }
            else { portal }
            if let notice=store.registrationNotice, store.access != nil, store.access?.patient_id == nil {
                Text(notice).font(.footnote).foregroundStyle(HospitalTheme.wine).padding(12)
                    .frame(maxWidth:.infinity).background(.white).accessibilityLabel(notice)
            }
            if let message = store.message {
                Text(message).font(.footnote).foregroundStyle(.red).padding(12)
                    .frame(maxWidth: .infinity).background(.white).accessibilityLabel("Aviso: \(message)")
            }
        }
        .foregroundStyle(HospitalTheme.ink).tint(HospitalTheme.wine)
        .background(HospitalTheme.background).preferredColorScheme(.light)
        .overlay { if store.busy { ProgressView().padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)) } }
        .task { await store.restore() }
        .task(id: "\(store.selectedRole ?? "")/\(store.screenID)") {
            search = ""
            await store.refreshScreen()
        }
        .onChange(of: store.selectedRole) { _, _ in showLabDesign = false; notificationsPresented = false; labDesign.reset(); appointmentFlow.reset() }
        .onChange(of: store.doctor?.workspace?.doctor_name) { _, name in
            if store.selectedRole == "doctor", let name { labDesign.doctorName = name }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && store.selectedRole != nil { Task { await store.refreshScreen() } }
        }
        .task(id: store.selectedRole) {
            while store.selectedRole == "doctor" && !Task.isCancelled {
                if scenePhase == .active { await store.doctor?.refreshAlerts() }
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
            }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            if scenePhase == .active && store.attention?.saving != true && ((store.selectedRole == "patient" && ["home", "appointments", "request", "health", "schedule", "turns", "notifications"].contains(store.screenID)) ||
                (store.selectedRole == "doctor" && ["home", "patients", "notifications"].contains(store.screenID))) {
                Task { await store.refreshScreen() }
            }
            // Avisos del paciente (resultados, citas, recetas): se actualizan cada 30 s en primer plano.
            if scenePhase == .active && store.selectedRole == "patient", let notices = store.patientNotifications, !notices.saving {
                Task { await notices.load("notifications") }
            }
            if scenePhase == .active && store.selectedRole == "doctor" && ["consultation", "agenda"].contains(store.screenID) {
                // Agenda: solo vuelve a pedirla si planning_revision cambió; no interrumpe una consulta abierta.
                Task { await store.doctor?.syncAgendaIfChanged() }
            }
        }
    }

    private var login: some View {
        VStack(spacing: 0) {
            HospitalAuthHeader(title: "Iniciar sesión", subtitle: "Accede a tu espacio de Médico o Paciente.")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HospitalCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Correo electrónico").font(.subheadline.weight(.semibold))
                            TextField("nombre@correo.com", text: $email)
                                .textContentType(.username).textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress).autocorrectionDisabled()
                                .padding(14).background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 12))
                            Text("Contraseña").font(.subheadline.weight(.semibold))
                            HStack {
                                Group {
                                    if showPassword { TextField("Contraseña", text: $password) }
                                    else { SecureField("Contraseña", text: $password) }
                                }.textContentType(.password).autocorrectionDisabled().textInputAutocapitalization(.never)
                                Button { showPassword.toggle() } label: { Image(systemName: showPassword ? "eye.slash" : "eye").foregroundStyle(HospitalTheme.secondary) }
                                    .accessibilityLabel(showPassword ? "Ocultar contraseña" : "Mostrar contraseña")
                            }.padding(14).background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 12))
                            HStack {
                                Spacer()
                                HospitalLink("¿Olvidaste tu contraseña?") { showRecoveryInfo = true }
                            }
                        }
                    }.padding(.top, -28)
                    Button {
                        let value = password; password = ""
                        Task { await store.signIn(email: email, password: value) }
                    } label: { Text("Iniciar sesión") }
                        .buttonStyle(HospitalPrimaryButtonStyle())
                        .disabled(store.busy || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                    HStack(spacing: 4) {
                        Text("¿No tienes cuenta?").font(.footnote).foregroundStyle(HospitalTheme.secondary)
                        HospitalLink("Regístrate") { showRegister = true }
                    }.frame(maxWidth: .infinity)
                    HospitalLink("Vista de diseño del solicitante") { showApplicantDemo = true }
                        .frame(maxWidth: .infinity)
                    Text("Tu perfil y tus permisos son asignados por el hospital.")
                        .font(.footnote).foregroundStyle(HospitalTheme.secondary).frame(maxWidth: .infinity, alignment: .center)
                }.padding(.horizontal, 16).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .alert("Recuperación de contraseña", isPresented: $showRecoveryInfo) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text("Solicita el restablecimiento con el personal del hospital. Enviarán las instrucciones a tu correo electrónico.")
        }
    }


    private var rolePicker: some View {
        VStack(spacing: 24) {
            Text("Selecciona tu perfil").font(.title.bold())
            ForEach(store.roles, id: \.self) { role in
                Button(role == "doctor" ? "Médico" : "Paciente") { store.selectRole(role) }
                    .buttonStyle(.borderedProminent).disabled(store.busy)
            }
            Button("Cerrar sesión") { Task { await store.signOut() } }.disabled(store.busy)
        }.padding().frame(maxHeight: .infinity)
    }

    private var screen: HospitalScreen? { store.screens.first { $0.id == store.screenID } }
    private var isDoctor: Bool { store.selectedRole == "doctor" }
    private var title: String {
        if isDoctor && store.screenID == "home" { return "Panel general" }
        if isDoctor && store.screenID == "agenda" { return "Agenda médica" }
        if !isDoctor && store.screenID == "home" { return "Mi espacio de salud" }
        if store.screenID == "home" { return "Hola, \(store.name == "Bienvenido" ? (isDoctor ? "Doctor" : "Paciente") : store.name)" }
        if !isDoctor && ["request", "schedule", "health"].contains(store.screenID) { return "Solicitar atención" }
        return screen?.title ?? (store.screenID == "rooms" ? "Habitaciones" : store.screenID == "health" ? "Mi salud" : "Más")
    }

    private var portal: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Hospital Universitario").font(.system(size: 14, weight: .medium))
                    Spacer()
                    if isDoctor, let doctor = store.doctor {
                        DoctorNotificationBell(model: doctor, isPresented: $notificationsPresented)
                    } else if store.selectedRole == "patient", let notices = store.patientNotifications {
                        PatientNotificationBell(model: notices, isPresented: $notificationsPresented, navigate: go)
                    } else {
                        Button { go("notifications") } label: { Image(systemName: "bell") }.accessibilityLabel("Notificaciones")
                    }
                }.padding(.bottom, 24)
                Text(title).font(.system(size: 25, weight: .semibold)).lineLimit(2)
                Text(screen?.subtitle ?? (store.screenID == "schedule" ? "Elige especialidad y horario" : "Servicios y consultas del hospital")).font(.system(size: 12)).padding(.top, 8)
            }
            .foregroundStyle(.white).padding(.horizontal, 24).padding(.top, 18).padding(.bottom, (store.screenID == "profile" || (isDoctor && store.screenID == "home") || (!isDoctor && ["chart", "laboratory", "appointments", "request", "schedule", "health", "information"].contains(store.screenID)) || (showLabDesign && ["patients", "chart", "laboratory"].contains(store.screenID))) ? 24 : 48)
            .frame(maxWidth: .infinity, alignment: .leading).background(HospitalTheme.wine.ignoresSafeArea(edges: .top))
            if store.screenID != "profile" && !(isDoctor && ["home","patients","laboratory","admissions"].contains(store.screenID)) && !(!isDoctor && ["home", "chart", "laboratory", "appointments", "request", "schedule", "health", "information"].contains(store.screenID)) && !(showLabDesign && ["patients", "chart", "laboratory"].contains(store.screenID)) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 11))
                TextField(isDoctor && ["agenda","consultation","patients"].contains(store.screenID) ? "Buscar paciente o expediente…" : screen?.search ?? "Buscar servicios…", text: $search).font(.system(size: 12)).autocorrectionDisabled()
                    .accessibilityLabel(screen?.search ?? "Buscar servicios")
            }.foregroundStyle(HospitalTheme.secondary).padding(.horizontal, 16).frame(height: 52)
                .background(.white, in: RoundedRectangle(cornerRadius: 13)).padding(.horizontal, 16).padding(.top, -29)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let note = store.screenMessage { Text(note).font(.footnote).foregroundStyle(HospitalTheme.secondary) }
                    content
                }.padding(.horizontal, 17).padding(.top, 22).padding(.bottom, 24)
            }.refreshable { await store.refreshScreen() }
            bottomBar
        }
    }

    @ViewBuilder private var content: some View {
        if isDoctor { liveContent }
        else if !isDoctor && ["chart", "laboratory", "appointments", "request", "schedule", "health", "information"].contains(store.screenID) { liveContent }
        else if ["patients", "chart", "laboratory"].contains(store.screenID) {
            VStack(alignment: .leading, spacing: 18) {
                Toggle("Vista de diseño · datos locales", isOn: $showLabDesign).font(.footnote)
                if showLabDesign {
                    ClinicalLabDesignView(model: labDesign, role: isDoctor ? "doctor" : "patient", screenID: store.screenID, navigate: go)
                        .onAppear {
                            if isDoctor {
                                labDesign.configureDoctor(name: store.doctor?.workspace?.doctor_name ?? store.name,
                                    id: store.access?.staff_id?.uuidString ?? "doctor-demo", clinic: store.doctor?.workspace?.facility_name)
                            }
                        }
                } else { liveContent }
            }
        } else { liveContent }
    }

    @ViewBuilder private var liveContent: some View {
        if !isDoctor, ["request", "schedule", "health"].contains(store.screenID), let attention = store.attention {
            PatientAttentionLiveView(model: attention, navigate: go)
        } else if !isDoctor, store.access?.patient_id == nil, ["appointments", "laboratory", "prescriptions", "chart", "history"].contains(store.screenID) {
            HospitalCard {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "heart.text.clipboard").font(.largeTitle).foregroundStyle(HospitalTheme.wine)
                    Text(store.screenID == "appointments" ? "No tienes citas programadas" : store.screenID == "laboratory" ? "No tienes resultados de laboratorio" : store.screenID == "prescriptions" ? "No tienes recetas disponibles" : "Tu información clínica aún no está disponible")
                        .font(.headline)
                    Text("Acércate a recepción o consulta los canales oficiales de contacto del hospital. El personal debe crear o vincular tu expediente y programar tu atención.")
                        .font(.subheadline).foregroundStyle(HospitalTheme.secondary)
                    Button("Información del hospital") { go("information") }
                    Button("Actualizar estado") { Task { await store.refreshScreen() } }
                }
            }
        } else if isDoctor, store.screenID == "prescriptions", let doctor = store.doctor {
            DoctorModuleView(model: doctor, screenID: "prescriptions", search: search, navigate: go, period: store.period)
        } else if !isDoctor, store.screenID == "appointments", let modules = store.modules {
            PatientAppointmentsView(flow: appointmentFlow, modules: modules, profile: store.profile, patientID: store.access?.patient_id, search: search, period: store.period, navigate: go)
        } else if !isDoctor, ["chart", "laboratory"].contains(store.screenID), let modules = store.modules, let laboratory = store.patientLaboratory {
            PatientClinicalView(model: modules, laboratory: laboratory, module: store.screenID, profile: store.profile, navigate: go)
        } else if !isDoctor, store.screenID == "prescriptions", let modules = store.modules {
            let useExamples = false
            PatientPrescriptionsView(records: useExamples ? PatientPrescriptionRecord.examples : modules.items.map(PatientPrescriptionRecord.from),
                demonstration: useExamples, search: search, loading: modules.loading, error: modules.error, hasMore: modules.page?.has_more == true,
                retry: { Task { await modules.load("prescriptions") } }, loadMore: { Task { await modules.load("prescriptions", more: true) } })
        } else if !isDoctor, store.screenID == "history", let modules = store.modules {
            let useExamples = false
            PatientHistoryView(records: useExamples ? PatientHistoryRecord.examples : modules.items.map(PatientHistoryRecord.from),
                demonstration: useExamples, search: search, loading: modules.loading, error: modules.error, hasMore: modules.page?.has_more == true,
                retry: { Task { await modules.load("history") } }, loadMore: { Task { await modules.load("history", more: true) } })
        } else if let modules = store.modules,
           ((!isDoctor && ["appointments", "request", "chart", "history", "prescriptions", "laboratory"].contains(store.screenID)) || (!isDoctor && store.screenID == "notifications")) {
            MobileModuleView(model: modules, module: store.screenID, role: isDoctor ? "doctor" : "patient", search: search, period: store.period, navigate: go)
        } else if isDoctor, let doctor = store.doctor,
           ["home", "agenda", "patients", "consultation", "chart", "laboratory", "notifications", "admissions"].contains(store.screenID) {
            DoctorModuleView(model: doctor, screenID: store.screenID, search: search, navigate: go, period: store.period)
        } else {
            switch store.screenID {
            case "home": if isDoctor { home } else { patientDashboard }
            case "schedule": PatientAppointmentView(flow: appointmentFlow)
            case "more", "health": menu
            case "turns": if isDoctor { schedule } else { queue }
            case "rooms": rooms
            case "profile": profile
            case "information": information
            default: menu
            }
        }
    }

    private func heading(_ value: String) -> some View { Text(value).font(.system(size: 16, weight: .semibold)).padding(.top, 1) }
    private func go(_ id: String) { if isDoctor && id == "notifications" { notificationsPresented = true; return }; notificationsPresented = false; guard !store.busy, store.doctor?.saving != true, store.modules?.saving != true, store.attention?.saving != true else { return }; if id == "consultation", store.screenID != id, store.doctor?.selectedAppointmentID == nil { store.doctor?.day = Date() }; store.screenID = id; search = "" }
    private func matches(_ value: String) -> Bool { search.isEmpty || value.localizedCaseInsensitiveContains(search) }

    /// Inicio del paciente: dashboard nuevo con saludo, fecha/cita y accesos rápidos.
    /// Usa el perfil autenticado; el vínculo clínico solo condiciona las lecturas clínicas.
    private var patientDashboard: some View {
        PatientDashboardView(
            nombrePaciente: store.access?.profile?.greeting_name ?? "",
            proximaCita: store.nextAppointment,
            sinExpediente: store.access?.patient_id == nil,
            cargando: store.busy,
            error: store.message,
            retry: { Task { await store.refreshScreen() } },
            navigate: go
        )
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading(screen?.section ?? "Resumen")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metric(store.summary.map { String((isDoctor ? $0.scheduled_appointments : $0.upcoming_appointments) ?? 0) } ?? "—", label: isDoctor ? "Citas programadas" : "Próximas citas", destination: isDoctor ? "patients" : "appointments")
                metric(store.summary.map { String((isDoctor ? $0.waiting_patients : $0.new_results) ?? 0) } ?? "—", label: isDoctor ? "Pacientes en espera" : "Resultado nuevo", destination: isDoctor ? "patients" : "laboratory")
                metric(store.summary.map { String((isDoctor ? $0.new_results : $0.active_prescriptions) ?? 0) } ?? "—", label: isDoctor ? "Resultados nuevos" : "Recetas activas", destination: isDoctor ? "laboratory" : "prescriptions")
                metric(isDoctor ? (store.summary.map { String($0.pending_prescriptions ?? 0) } ?? "—") : "—", label: isDoctor ? "Recetas pendientes" : "Turno actual", destination: isDoctor ? "prescriptions" : "turns")
            }
            heading(isDoctor ? "Accesos clínicos" : "Accesos rápidos")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                shortcut(isDoctor ? "Mis pacientes" : "Solicitar atención", icon: isDoctor ? "person" : "cross.fill", id: isDoctor ? "patients" : "request")
                shortcut(isDoctor ? "Iniciar consulta" : "Mis citas", icon: isDoctor ? "cross.fill" : "calendar", id: isDoctor ? "consultation" : "appointments")
                shortcut(isDoctor ? "Laboratorio" : "Mi expediente", icon: isDoctor ? "testtube.2" : "doc.text", id: isDoctor ? "laboratory" : "chart")
                shortcut(isDoctor ? "Recetas" : "Laboratorio", icon: isDoctor ? "doc.text" : "testtube.2", id: isDoctor ? "prescriptions" : "laboratory")
            }
        }
    }

    private func metric(_ value: String, label: String, destination: String) -> some View {
        Button { go(destination) } label: {
            HospitalCard {
                Text(value).font(.system(size: 25, weight: .semibold)).foregroundStyle(HospitalTheme.wine)
                Text(label).font(.system(size: 10)).foregroundStyle(HospitalTheme.secondary).padding(.top, 12)
            }.frame(minHeight: 96)
        }.buttonStyle(.plain).disabled(store.busy)
    }

    @ViewBuilder private func shortcut(_ label: String, icon: String, id: String) -> some View {
        if matches(label) {
            Button { go(id) } label: {
                HospitalCard {
                    Image(systemName: icon).foregroundStyle(HospitalTheme.wine).font(.system(size: 20))
                    Text(label).font(.system(size: 11, weight: .medium)).padding(.top, 10)
                }.frame(minHeight: 95)
            }.buttonStyle(.plain).disabled(store.busy)
        }
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading(store.screenID == "health" ? "Tu información de salud" : "Servicios")
            ForEach(store.screens.filter { $0.id != "home" && (store.screenID != "health" || $0.tab == "health") && matches($0.title) }) { item in
                Button { go(item.id) } label: {
                    HospitalCard { HStack { Text(item.title).font(.subheadline); Spacer(); Image(systemName: "chevron.right").font(.caption) } }
                }.buttonStyle(.plain).disabled(store.busy)
            }
            if matches("Habitaciones") { shortcut("Habitaciones", icon: "bed.double", id: "rooms") }
            if store.roles.count > 1 { Button("Cambiar perfil") { store.switchRole() }.disabled(store.busy) }
            Button("Cerrar sesión") { Task { await store.signOut() } }.disabled(store.busy).frame(maxWidth: .infinity).padding()
        }
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("Próxima jornada")
            if let next = store.nextShift {
                HospitalCard { Text(store.period(next.period)).font(.subheadline.weight(.semibold)); HospitalBadge(text: HospitalLabels.status(next.status), warning: next.status != "confirmed") }
            } else { empty("No tienes jornadas asignadas.") }
            heading("Agenda semanal")
            ForEach(store.orderedShifts.filter { matches(store.period($0.period)) }) { shift in
                HospitalCard {
                    Text(store.period(shift.period)).font(.system(size: 12, weight: .medium))
                    HospitalBadge(text: HospitalLabels.status(shift.status), warning: shift.status != "confirmed")

                }
            }
            if store.shiftsMore { Button("Cargar más") { Task { await store.refreshScreen(more: true) } }.disabled(store.busy) }
            if let error = store.modules?.error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
    }

    private var queue: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("Turno de atención")
            HospitalNotice(text: "Hospital Móviles no publica una fila numerada. Consulta tus citas para conocer la atención programada.")
            Button("Mis citas") { store.screenID = "appointments" }
        }
    }

    private var rooms: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Habitaciones del hospital")
            ForEach(store.rooms.filter { matches($0.code) }) { room in
                HospitalCard { Label(room.code, systemImage: "bed.double").font(.subheadline.weight(.semibold)); HospitalBadge(text: room.active ? "Activa" : "Inactiva", warning: !room.active) }
            }
            if store.rooms.isEmpty { empty("No hay habitaciones disponibles para consultar.") }
            Text("El estado activo no indica disponibilidad de camas.").font(.caption).foregroundStyle(HospitalTheme.secondary)
            if store.roomsMore { Button("Cargar más") { Task { await store.refreshScreen(more: true) } }.disabled(store.busy) }
        }
    }

    private var profile: some View {
        let given = store.profile?.person?.given_names.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let family = store.profile?.person?.family_names.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Group {
            if !isDoctor {
                PatientProfileCardView(name: [given, family].filter { !$0.isEmpty }.joined(separator: " "), email: store.profile?.auth_email ?? "", phone: store.profile?.contacts.first { $0.kind == "phone" }?.value ?? "")
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 48)).foregroundStyle(HospitalTheme.wine)
                        Text("Datos de registro").font(.system(size: 22, weight: .bold)).foregroundStyle(HospitalTheme.ink)
                    }.padding(.vertical, 10)
                    HospitalCard { DoctorConsultationField(label: "Nombre", value: given.isEmpty ? "No disponible" : given) }
                    HospitalCard { DoctorConsultationField(label: "Apellido", value: family.isEmpty ? "No disponible" : family) }
                }
            }
        }
    }

    private var information: some View {
        HospitalInformationView(overview: store.overview, navigate: go)
    }

    private func empty(_ text: String) -> some View { HospitalCard { Text(text).font(.system(size: 12)).foregroundStyle(HospitalTheme.secondary).padding(.vertical, 15) } }
    private func detail(_ title: String, value: String) -> some View {
        HospitalCard { Text(title).font(.system(size: 12, weight: .semibold)); Text(value).font(.system(size: 11)).foregroundStyle(HospitalTheme.secondary) }
    }

    private var bottomBar: some View {
        let tabs: [(String, String, String)] = isDoctor ? [("home","Inicio","house"),("patients","Pacientes","person"),("consultation","Consultas","cross.fill"),("laboratory","Laboratorios","testtube.2"),("more","Más","line.3.horizontal")] : [("home","Inicio","house"),("appointments","Mis citas","calendar"),("health","Salud","heart"),("profile","Perfil","person"),("more","Más","line.3.horizontal")]
        let active = !isDoctor && ["request", "schedule", "health"].contains(store.screenID) ? "health" : ["more", "health", "rooms"].contains(store.screenID) ? (store.screenID == "health" ? "health" : "more") : screen?.tab ?? "home"
        return HStack(spacing: 0) {
            ForEach(tabs.indices, id: \.self) { index in
                let (id, label, icon) = tabs[index]
                Button { go(id) } label: {
                    VStack(spacing: 6) { Image(systemName: icon).font(.system(size: 16)); Text(label).font(.system(size: 9)) }
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .foregroundStyle(active == id ? HospitalTheme.wine : HospitalTheme.secondary)
                        .background(active == id ? HospitalTheme.rose : .clear, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).disabled(store.busy).accessibilityAddTraits(active == id ? .isSelected : [])
            }
        }.padding(.horizontal, 12).padding(.top, 7).background(Color.white.ignoresSafeArea(edges: .bottom))
    }
}

@MainActor
/// Campana del paciente: sus avisos propios (resultados publicados, citas, recetas, solicitudes), igual que el médico.
private struct PatientNotificationBell: View {
    @ObservedObject var model: MobileModuleViewModel
    @Binding var isPresented: Bool
    let navigate: (String) -> Void
    @State private var reading: UUID?
    private var unread: Int { model.items.filter { $0.status == "unread" }.count }
    private func icon(_ item: MobileItem) -> String {
        let text = (item.title + " " + (item.subtitle ?? "")).lowercased()
        if text.contains("laboratorio") || text.contains("resultado") { return "testtube.2" }
        if text.contains("receta") { return "pills.fill" }
        if text.contains("cita") { return "calendar" }
        if text.contains("solicitud") { return "text.bubble" }
        return "bell"
    }
    private func destination(_ item: MobileItem) -> String? {
        ["testtube.2": "laboratory", "pills.fill": "prescriptions", "calendar": "appointments", "text.bubble": "request"][icon(item)]
    }
    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: unread > 0 ? "bell.badge.fill" : "bell").font(.title3)
                if unread > 0 { Text("\(unread)").font(.caption.bold()).padding(5).background(.white.opacity(0.2), in: Capsule()) }
            }.frame(minWidth: 44, minHeight: 44)
        }.accessibilityLabel("Notificaciones").accessibilityValue("\(unread) sin leer")
            .task { if model.items.isEmpty { await model.load("notifications") } }
            .popover(isPresented: $isPresented, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mis avisos").font(.title3.bold())
                            Text(unread == 0 ? "Estás al día" : "\(unread) sin leer").font(.caption).foregroundStyle(HospitalTheme.secondary)
                        }
                        Spacer()
                        Button { isPresented = false } label: { Image(systemName: "xmark.circle.fill").font(.title2) }.accessibilityLabel("Cerrar notificaciones")
                    }
                    Divider()
                    if let error = model.error { Text(error).font(.footnote).foregroundStyle(.red) }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if model.items.isEmpty && !model.loading {
                                VStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle").font(.title).foregroundStyle(HospitalTheme.wine)
                                    Text("No tienes avisos recientes.").font(.subheadline)
                                    Text("Te avisaremos cuando tengas una cita, resultados o una receta lista.").font(.caption).foregroundStyle(HospitalTheme.secondary).multilineTextAlignment(.center)
                                }.frame(maxWidth: .infinity).padding(.vertical, 24)
                            }
                            ForEach(model.items) { item in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: icon(item)).font(.subheadline.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
                                        .frame(width: 34, height: 34).background(.white, in: Circle())
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.title).font(.subheadline.bold()).foregroundStyle(HospitalTheme.ink)
                                        if let body = item.subtitle { Text(body).font(.footnote).fixedSize(horizontal: false, vertical: true) }
                                        Text(DoctorDate.display(item.event_at)).font(.caption2).foregroundStyle(HospitalTheme.secondary)
                                        HStack(spacing: 14) {
                                            if let target = destination(item) { Button("Ver") { isPresented = false; navigate(target) }.font(.caption.bold()) }
                                            if item.status == "unread" {
                                                Button(reading == item.id ? "Guardando…" : "Marcar como leída") {
                                                    reading = item.id
                                                    Task { await model.markRead(item); reading = nil }
                                                }.font(.caption.bold()).disabled(reading != nil)
                                            }
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(item.status == "unread" ? HospitalTheme.rose : HospitalTheme.background, in: RoundedRectangle(cornerRadius: 14))
                            }
                            if model.page?.has_more == true { Button("Cargar más avisos") { Task { await model.load("notifications", more: true) } } }
                        }
                    }
                    Button("Actualizar avisos", systemImage: "arrow.clockwise") { Task { await model.load("notifications") } }.font(.caption.bold())
                }.padding(18).frame(width: 320, height: 460).foregroundStyle(HospitalTheme.ink).tint(HospitalTheme.wine)
                    .background(.white).presentationCompactAdaptation(.popover)
                    .task { await model.load("notifications") }
            }
    }
}

private struct DoctorNotificationBell: View {
    @ObservedObject var model: DoctorViewModel
    @Binding var isPresented: Bool
    @State private var reading: UUID?
    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: model.unreadAlerts > 0 ? "bell.badge.fill" : "bell").font(.title3)
                if model.unreadAlerts > 0 { Text("\(model.unreadAlerts)").font(.caption.bold()).padding(5).background(.white.opacity(0.2), in: Capsule()) }
            }.frame(minWidth: 44, minHeight: 44)
        }.accessibilityLabel("Notificaciones").accessibilityValue("\(model.unreadAlerts) sin leer")
            .popover(isPresented: $isPresented, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notificaciones").font(.title3.bold())
                            Text("\(model.unreadAlerts) sin leer").font(.caption).foregroundStyle(HospitalTheme.secondary)
                        }
                        Spacer()
                        Button { isPresented = false } label: { Image(systemName: "xmark.circle.fill").font(.title2) }.accessibilityLabel("Cerrar notificaciones")
                    }
                    Divider()
                    if let error = model.alertsError { Text(error).font(.footnote).foregroundStyle(.red) }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if model.alerts.isEmpty { Label("Estás al día. No hay avisos recientes.", systemImage: "checkmark.circle").font(.subheadline).padding(.vertical, 24) }
                            ForEach(model.alerts) { item in
                                VStack(alignment: .leading, spacing: 8) {
                                    Label(item.title, systemImage: item.read_at == nil ? "circle.fill" : "checkmark.circle").font(.subheadline.bold()).foregroundStyle(HospitalTheme.wine)
                                    Text(item.body).font(.footnote).fixedSize(horizontal: false, vertical: true)
                                    Text(DoctorDate.display(item.created_at)).font(.caption2).foregroundStyle(HospitalTheme.secondary)
                                    if item.read_at == nil {
                                        Button(reading == item.id ? "Guardando…" : "Marcar como leída") {
                                            reading = item.id
                                            Task { await model.markRead(item); reading = nil }
                                        }.font(.caption.bold()).disabled(reading != nil)
                                    } else { Text("Leída").font(.caption).foregroundStyle(HospitalTheme.secondary) }
                                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(item.read_at == nil ? HospitalTheme.rose : HospitalTheme.background, in: RoundedRectangle(cornerRadius: 14))
                            }
                            if model.alertsHaveMore { Button("Cargar más avisos") { Task { await model.refreshAlerts(more: true) } } }
                        }
                    }
                    HStack {
                        Button("Actualizar avisos", systemImage: "arrow.clockwise") { Task { await model.refreshAlerts() } }
                        Spacer()
                        Button("Recordatorios") { Task { await model.enableReminders() } }
                    }.font(.caption.bold())
                    if let message = model.notificationMessage { Text(message).font(.caption).foregroundStyle(HospitalTheme.secondary) }
                }.padding(18).frame(width: 310, height: 440).foregroundStyle(HospitalTheme.ink).tint(HospitalTheme.wine)
                    .background(.white).presentationCompactAdaptation(.popover)
                    .task { await model.refreshAlerts() }
            }
    }
}
