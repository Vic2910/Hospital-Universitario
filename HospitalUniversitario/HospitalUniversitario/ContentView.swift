import SwiftUI

@MainActor
struct ContentView: View {
    @StateObject private var store = HospitalStore()
    @StateObject private var labDesign = ClinicalLabDesignStore()
    @State private var showLabDesign = false
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var showRegister = false
    @State private var showRecoveryInfo = false
    @State private var search = ""
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            if store.access == nil {
                if showRegister { RegisterView(store: store, onBack: { showRegister = false }) }
                else { login }
            }
            else if store.selectedRole == nil { rolePicker }
            else { portal }
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
        .onChange(of: store.selectedRole) { _, _ in showLabDesign = store.selectedRole == "doctor"; labDesign.reset() }
        .onChange(of: store.doctor?.workspace?.doctor_name) { _, name in
            if store.selectedRole == "doctor", let name { labDesign.doctorName = name }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && store.selectedRole != nil { Task { await store.refreshScreen() } }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            if scenePhase == .active && ((store.selectedRole == "patient" && ["turns", "notifications"].contains(store.screenID)) ||
                (store.selectedRole == "doctor" && ["home", "patients", "notifications"].contains(store.screenID))) {
                Task { await store.refreshScreen() }
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
                    Button { go("notifications") } label: { Image(systemName: "bell.badge") }.accessibilityLabel("Notificaciones")
                }.padding(.bottom, 24)
                Text(title).font(.system(size: 25, weight: .semibold)).lineLimit(2)
                Text(screen?.subtitle ?? (store.screenID == "schedule" ? "Elige especialidad y horario" : "Servicios y consultas del hospital")).font(.system(size: 12)).padding(.top, 8)
            }
            .foregroundStyle(.white).padding(.horizontal, 24).padding(.top, 18).padding(.bottom, (store.screenID == "profile" || (!isDoctor && ["chart", "laboratory", "appointments", "request", "schedule", "health", "information"].contains(store.screenID)) || (showLabDesign && ["patients", "chart", "laboratory"].contains(store.screenID))) ? 24 : 48)
            .frame(maxWidth: .infinity, alignment: .leading).background(HospitalTheme.wine.ignoresSafeArea(edges: .top))
            if store.screenID != "profile" && !(!isDoctor && ["chart", "laboratory", "appointments", "request", "schedule", "health", "information"].contains(store.screenID)) && !(showLabDesign && ["patients", "chart", "laboratory"].contains(store.screenID)) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 11))
                TextField(screen?.search ?? "Buscar servicios…", text: $search).font(.system(size: 12)).autocorrectionDisabled()
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
        if !isDoctor && ["chart", "laboratory", "appointments", "request", "schedule", "health", "information"].contains(store.screenID) { liveContent }
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
        if isDoctor, store.screenID == "prescriptions", let doctor = store.doctor, let modules = store.modules {
            DoctorPrescriptionView(doctor: doctor, model: modules, search: search, period: store.period, navigate: go)
        } else if !isDoctor, ["request", "schedule", "health"].contains(store.screenID), let modules = store.modules {
            PatientAppointmentRealView(model: modules, profile: store.profile)
        } else if !isDoctor, store.screenID == "appointments", let modules = store.modules {
            PatientAppointmentsView(modules: modules, profile: store.profile, patientID: store.access?.patient_id, search: search, period: store.period, navigate: go)
        } else if !isDoctor, ["chart", "laboratory"].contains(store.screenID), let modules = store.modules, let laboratory = store.patientLaboratory {
            PatientClinicalView(model: modules, laboratory: laboratory, module: store.screenID, profile: store.profile, navigate: go)
        } else if !isDoctor, store.screenID == "prescriptions", let modules = store.modules {
            PatientPrescriptionsView(records: modules.items.map(PatientPrescriptionRecord.from),
                demonstration: false, search: search, loading: modules.loading, error: modules.error, hasMore: modules.page?.has_more == true,
                retry: { Task { await modules.load("prescriptions") } }, loadMore: { Task { await modules.load("prescriptions", more: true) } })
        } else if !isDoctor, store.screenID == "history", let modules = store.modules {
            PatientHistoryView(records: modules.items.map(PatientHistoryRecord.from),
                demonstration: false, search: search, loading: modules.loading, error: modules.error, hasMore: modules.page?.has_more == true,
                retry: { Task { await modules.load("history") } }, loadMore: { Task { await modules.load("history", more: true) } })
        } else if let modules = store.modules,
           ((!isDoctor && ["appointments", "request", "chart", "history", "prescriptions", "laboratory"].contains(store.screenID)) || store.screenID == "notifications") {
            MobileModuleView(model: modules, module: store.screenID, role: isDoctor ? "doctor" : "patient", search: search, period: store.period, navigate: go)
        } else if isDoctor, let doctor = store.doctor,
           ["home", "patients", "consultation", "chart", "laboratory", "notifications"].contains(store.screenID) {
            DoctorModuleView(model: doctor, screenID: store.screenID, search: search, navigate: go, period: store.period)
        } else {
            switch store.screenID {
            case "home": if isDoctor { home } else { patientDashboard }
            case "request", "schedule": empty("Preparando la solicitud de atención…")
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
    private func go(_ id: String) { guard !store.busy, store.doctor?.saving != true, store.modules?.saving != true else { return }; if id == "consultation", store.screenID != id, store.doctor?.selectedAppointmentID == nil { store.doctor?.day = Date() }; store.screenID = id; search = "" }
    private func matches(_ value: String) -> Bool { search.isEmpty || value.localizedCaseInsensitiveContains(search) }

    /// Inicio del paciente: dashboard con saludo, fecha/cita real y accesos rápidos.
    /// La próxima cita proviene del módulo `appointments` (cargado en `home`).
    private var patientDashboard: some View {
        PatientDashboardView(
            nombrePaciente: store.name == "Bienvenido" ? "Paciente" : store.name,
            proximaCita: nextPatientAppointment,
            navigate: go
        )
    }

    /// Próxima cita confirmada o programada del paciente, desde los ítems reales del módulo.
    private var nextPatientAppointment: ProximaCita? {
        guard let items = store.modules?.items else { return nil }
        let now = Date()
        guard let item = items.filter({ ["scheduled", "confirmed"].contains($0.status) && (DoctorDate.parse($0.event_at) ?? .distantPast) >= now })
            .sorted(by: { (DoctorDate.parse($0.event_at) ?? .distantPast) < (DoctorDate.parse($1.event_at) ?? .distantPast) }).first,
              let date = DoctorDate.parse(item.event_at) else { return nil }
        func field(_ label: String) -> String? { item.details.first { $0.label.localizedCaseInsensitiveCompare(label) == .orderedSame }?.value }
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "es_SV")
        dayFormatter.dateFormat = "d 'de' MMMM"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "es_SV")
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none
        return ProximaCita(dia: dayFormatter.string(from: date), hora: timeFormatter.string(from: date),
                           medico: field("Medico") ?? item.title)
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading(screen?.section ?? "Resumen")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metric(store.summary.map { String((isDoctor ? $0.scheduled_appointments : $0.upcoming_appointments) ?? 0) } ?? "—", label: isDoctor ? "Citas programadas" : "Próximas citas", destination: isDoctor ? "patients" : "appointments")
                metric(store.summary.map { String((isDoctor ? $0.waiting_patients : $0.new_results) ?? 0) } ?? "—", label: isDoctor ? "Pacientes en espera" : "Resultado nuevo", destination: isDoctor ? "patients" : "laboratory")
                metric(store.summary.map { String((isDoctor ? $0.new_results : $0.active_prescriptions) ?? 0) } ?? "—", label: isDoctor ? "Resultados nuevos" : "Recetas activas", destination: isDoctor ? "laboratory" : "prescriptions")
                metric(isDoctor ? (store.summary.map { String($0.pending_prescriptions ?? 0) } ?? "—") : store.summary?.tickets?.first.map { String($0.number) } ?? "—", label: isDoctor ? "Recetas pendientes" : "Turno actual", destination: isDoctor ? "prescriptions" : "turns")
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
                    if shift.status == "pending", let modules = store.modules {
                        Button("Confirmar jornada", systemImage: "calendar.badge.checkmark") {
                            Task { if await modules.confirmShift(id: shift.id, version: Int(shift.row_version)) { await store.refreshScreen() } }
                        }.disabled(modules.saving)
                    }
                }
            }
            if store.shiftsMore { Button("Cargar más") { Task { await store.refreshScreen(more: true) } }.disabled(store.busy) }
            if let error = store.modules?.error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
    }

    private var queue: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("Turno de atención")
            if store.queueStatuses.isEmpty { empty("No tienes un turno activo.") }
            ForEach(store.queueStatuses, id: \.ticket_id) { status in
                HospitalCard {
                    VStack(spacing: 22) {
                        Text("Tu número").font(.system(size: 12)).foregroundStyle(HospitalTheme.secondary)
                        Text(status.display_number ?? String(status.number)).font(.system(size: 42, weight: .semibold)).foregroundStyle(HospitalTheme.wine)
                        HospitalBadge(text: HospitalLabels.status(status.status), warning: status.status == "waiting")
                    }.frame(maxWidth: .infinity).padding(.vertical, 15)
                }
                heading("Información de la fila")
                detail("Turno actual en atención", value: status.serving_number ?? "Sin turno en atención")
                detail("Personas antes de ti", value: String(status.people_ahead))
                detail("Consultorio asignado", value: status.consultation_room?.name ?? "Por asignar")
            }
            if store.shiftsMore { Button("Cargar más") { Task { await store.refreshScreen(more: true) } }.disabled(store.busy) }
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
            if let modules = store.modules, modules.page != nil || modules.loading || modules.error != nil {
                MobileModuleView(model: modules, module: "profile", role: isDoctor ? "doctor" : "patient", search: search, period: store.period, navigate: go)
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
