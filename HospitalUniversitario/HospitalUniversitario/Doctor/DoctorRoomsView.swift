import SwiftUI

// MARK: - Modelos (RPC doctor_native_rooms / room_candidates / hospitalize / assign_bed / discharge)

struct DoctorRoomOccupant: Decodable, Equatable {
    let admission_id: UUID
    let patient_id: UUID
    let patient_name: String
    let record_number: String?
    let status: String
    let reason: String?
    let since: String?
}
struct DoctorRoomBed: Decodable, Identifiable, Equatable {
    let id: UUID
    let code: String
    let state: String
    let available: Bool
    let mine: Bool?
    let occupant: DoctorRoomOccupant?
    var stateLabel: String {
        ["disponible": "Disponible", "ocupada": "Ocupada", "limpieza": "En limpieza", "mantenimiento": "Mantenimiento"][state] ?? state.capitalized
    }
}
struct DoctorRoom: Decodable, Identifiable, Equatable {
    let id: UUID
    let code: String
    let kind: String
    let floor: String
    let active: Bool
    let beds: [DoctorRoomBed]
    var freeBeds: Int { beds.filter(\.available).count }
    var hasMine: Bool { beds.contains { $0.mine == true } }
}
struct DoctorHospitalized: Decodable, Identifiable, Equatable {
    let admission_id: UUID
    let patient_id: UUID
    let patient_name: String
    let record_number: String?
    let status: String
    let category: String
    let reason: String
    let observations: String?
    let priority: String
    let ordered_at: String
    let discharged_at: String?
    let discharge_notes: String?
    let room: String?
    let bed: String?
    let floor: String?
    let assigned_at: String?
    var id: UUID { admission_id }
}
struct DoctorRoomsBoard: Decodable { let rooms: [DoctorRoom]; let hospitalized: [DoctorHospitalized] }
struct DoctorRoomCandidate: Decodable, Identifiable, Equatable {
    let id: UUID
    let full_name: String
    let record_number: String?
    let dui: String?
    let last_consultation: String?
    let active_admission: String?
}

enum DoctorRoomText {
    static func date(_ value: String?) -> String {
        guard let value else { return "—" }
        return String(value.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }
}

// MARK: - ViewModel

@MainActor
final class DoctorRoomsModel: ObservableObject {
    @Published private(set) var board: DoctorRoomsBoard?
    @Published private(set) var candidates: [DoctorRoomCandidate] = []
    @Published private(set) var loading = false
    @Published private(set) var saving = false
    @Published var error: String?
    @Published var notice: String?
    private var hospitalizeKey = UUID()
    private let api: HospitalAPI

    init(api: HospitalAPI) { self.api = api }

    var pending: [DoctorHospitalized] { board?.hospitalized.filter { $0.status == "solicitado" } ?? [] }
    var admitted: [DoctorHospitalized] { board?.hospitalized.filter { $0.status != "solicitado" } ?? [] }
    func freeBeds(kind: String?) -> [(DoctorRoom, DoctorRoomBed)] {
        (board?.rooms ?? []).filter { $0.active && (kind == nil || $0.kind == kind) }.flatMap { r in r.beds.filter(\.available).map { (r, $0) } }
    }

    func load() async {
        loading = true; defer { loading = false }
        do { board = try await api.doctorRPC("rooms"); error = nil } catch { self.error = Self.describe(error) }
    }

    func search(_ query: String) async {
        do { candidates = try await api.doctorRPC("room_candidates", parameters: ["p_query": query]) }
        catch { candidates = []; self.error = Self.describe(error) }
    }

    /// Devuelve true si se guardó. Ante un conflicto (cama tomada por otro usuario) recarga el mapa.
    func hospitalize(patient: DoctorRoomCandidate, bed: DoctorRoomBed, reason: String, instructions: String, urgent: Bool) async -> Bool {
        await mutate(success: "\(patient.full_name) quedó hospitalizado en la cama \(bed.code).") {
            let _: DoctorJSON = try await self.api.doctorRPC("hospitalize", parameters: [
                "p_patient": patient.id.uuidString.lowercased(), "p_bed": bed.id.uuidString.lowercased(),
                "p_reason": reason, "p_instructions": instructions, "p_priority": urgent ? "urgente" : "normal",
                "p_key": self.hospitalizeKey.uuidString.lowercased()])
            self.hospitalizeKey = UUID()
        }
    }
    func assign(_ admission: DoctorHospitalized, bed: DoctorRoomBed) async -> Bool {
        await mutate(success: "Cama \(bed.code) asignada a \(admission.patient_name).") {
            let _: DoctorJSON = try await self.api.doctorRPC("assign_bed", parameters: ["p_admission": admission.admission_id.uuidString.lowercased(), "p_bed": bed.id.uuidString.lowercased()])
        }
    }
    func discharge(_ admissionID: UUID, name: String, notes: String) async -> Bool {
        await mutate(success: "Alta médica registrada para \(name). Recepción liberará la cama.") {
            let _: DoctorJSON = try await self.api.doctorRPC("discharge", parameters: ["p_admission": admissionID.uuidString.lowercased(), "p_notes": notes])
        }
    }

    private func mutate(success: String, _ work: @escaping @MainActor () async throws -> Void) async -> Bool {
        guard !saving else { return false }
        saving = true; error = nil; notice = nil
        defer { saving = false }
        do { try await work(); notice = success; await load(); return true }
        catch { self.error = Self.describe(error); await load(); return false }
    }

    static func describe(_ error: Error) -> String {
        if let failure = error as? HospitalError { return failure.localizedDescription }
        let detail = String(describing: error)
        if detail.contains("404") || detail.contains("PGRST202") { return "El módulo de habitaciones aún no está disponible en el servidor (migración pendiente)." }
        return error.localizedDescription
    }
}

// MARK: - Vista principal

struct DoctorRoomsView: View {
    @StateObject private var model: DoctorRoomsModel
    @State private var tab = 0
    @State private var openRoom: DoctorRoom?
    @State private var openPatient: DoctorHospitalized?
    @State private var hospitalizeBed: DoctorRoomBed?
    @State private var assigning: DoctorHospitalized?
    let search: String

    init(api: HospitalAPI, search: String) {
        _model = StateObject(wrappedValue: DoctorRoomsModel(api: api))
        self.search = search
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            summary
            Picker("Vista", selection: $tab) { Text("Habitaciones").tag(0); Text("Mis hospitalizados").tag(1) }.pickerStyle(.segmented)
            if let notice = model.notice { banner(notice, icon: "checkmark.circle.fill", color: Color(red: 0.13, green: 0.5, blue: 0.3)) }
            if let error = model.error { banner(error, icon: "exclamationmark.triangle.fill", color: .red) }
            if model.board == nil && model.loading { ProgressView("Cargando habitaciones…").frame(maxWidth: .infinity) }
            if tab == 0 { roomList } else { patientList }
        }
        .task { await model.load() }
        .refreshable { await model.load() }
        .sheet(item: $openRoom) { room in
            DoctorRoomDetailSheet(room: model.board?.rooms.first { $0.id == room.id } ?? room,
                                  hospitalize: { bed in openRoom = nil; afterSheet { hospitalizeBed = bed } },
                                  openPatient: { id in openRoom = nil; afterSheet { openPatient = model.board?.hospitalized.first { $0.admission_id == id } } })
        }
        .sheet(item: $openPatient) { patient in
            DoctorHospitalizedSheet(patient: patient, model: model)
        }
        .sheet(item: $hospitalizeBed) { bed in
            DoctorHospitalizeSheet(bed: bed, model: model)
        }
        .sheet(item: $assigning) { admission in
            DoctorAssignBedSheet(admission: admission, model: model)
        }
    }

    /// Presenta la siguiente hoja cuando la anterior terminó de cerrarse (SwiftUI no admite dos hojas a la vez).
    private func afterSheet(_ action: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: action) }

    private var summary: some View {
        let rooms = model.board?.rooms ?? []
        let beds = rooms.flatMap(\.beds)
        return VStack(alignment: .leading, spacing: 10) {
            Label("HABITACIONES", systemImage: "bed.double.fill").font(.caption2.weight(.heavy)).tracking(1.2).opacity(0.85)
            HStack(spacing: 18) {
                stat("\(beds.filter(\.available).count)", "Camas libres")
                stat("\(beds.filter { $0.state == "ocupada" }.count)", "Ocupadas")
                stat("\(model.admitted.filter { $0.status == "hospitalizado" }.count)", "Mis pacientes")
            }
        }.foregroundStyle(.white).padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(HospitalTheme.wine, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(value).font(.title2.bold()); Text(label).font(.caption).opacity(0.9) }
    }

    @ViewBuilder private var roomList: some View {
        let rooms = (model.board?.rooms ?? []).filter { search.isEmpty || $0.code.localizedCaseInsensitiveContains(search) || $0.floor.localizedCaseInsensitiveContains(search) }
        ForEach(rooms) { room in
            Button { openRoom = room } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bed.double").font(.title3).foregroundStyle(HospitalTheme.wine)
                        .frame(width: 42, height: 42).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(room.code) · \(DoctorAdmissionLabels.category(room.kind))").font(.subheadline.weight(.semibold)).foregroundStyle(HospitalTheme.ink)
                        Text("\(room.floor) · \(room.beds.count) cama(s)").font(.caption).foregroundStyle(HospitalTheme.secondary)
                    }
                    Spacer()
                    if room.hasMine { Image(systemName: "person.fill.checkmark").foregroundStyle(HospitalTheme.wine) }
                    pill(!room.active ? "Inactiva" : room.freeBeds > 0 ? "\(room.freeBeds) libre(s)" : "Ocupada",
                         color: !room.active ? .gray : room.freeBeds > 0 ? Color(red: 0.13, green: 0.5, blue: 0.3) : .red)
                }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 16)).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        if model.board != nil && rooms.isEmpty { Text("No hay habitaciones que coincidan.").foregroundStyle(HospitalTheme.secondary) }
    }

    @ViewBuilder private var patientList: some View {
        let match: (DoctorHospitalized) -> Bool = { search.isEmpty || $0.patient_name.localizedCaseInsensitiveContains(search) || ($0.record_number ?? "").localizedCaseInsensitiveContains(search) }
        if !model.pending.filter(match).isEmpty {
            Text("Pendientes de cama").font(.headline)
            ForEach(model.pending.filter(match)) { a in
                patientRow(a) { Button("Asignar cama") { assigning = a }.buttonStyle(.borderedProminent).tint(HospitalTheme.wine).controlSize(.small) }
            }
        }
        Text("Hospitalizados por mí").font(.headline)
        let admitted = model.admitted.filter(match)
        ForEach(admitted) { a in
            Button { openPatient = a } label: { patientRow(a) { Image(systemName: "chevron.right").foregroundStyle(HospitalTheme.secondary) } }.buttonStyle(.plain)
        }
        if model.board != nil && admitted.isEmpty { Text("No tienes pacientes hospitalizados.").font(.subheadline).foregroundStyle(HospitalTheme.secondary) }
    }

    private func patientRow<A: View>(_ a: DoctorHospitalized, @ViewBuilder accessory: () -> A) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(a.patient_name).font(.subheadline.weight(.semibold)).foregroundStyle(HospitalTheme.ink)
                Text([a.record_number, a.room.map { "\($0) · \(a.bed ?? "")" }, DoctorAdmissionLabels.status(a.status)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(HospitalTheme.secondary)
            }
            Spacer()
            accessory()
        }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 16)).contentShape(Rectangle())
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text).font(.caption2.bold()).foregroundStyle(color).padding(.horizontal, 8).padding(.vertical, 4).background(color.opacity(0.12), in: Capsule())
    }
    private func banner(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon).font(.footnote).foregroundStyle(color).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Detalle de habitación

struct DoctorRoomDetailSheet: View {
    let room: DoctorRoom
    let hospitalize: (DoctorRoomBed) -> Void
    let openPatient: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Habitación") {
                    row("Código", room.code); row("Categoría", DoctorAdmissionLabels.category(room.kind)); row("Piso", room.floor)
                    row("Estado", room.active ? "Activa" : "Inactiva"); row("Camas libres", "\(room.freeBeds) de \(room.beds.count)")
                }
                Section("Camas") {
                    ForEach(room.beds) { bed in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text("Cama \(bed.code)").font(.subheadline.weight(.semibold)); Spacer(); Text(bed.stateLabel).font(.caption.bold()).foregroundStyle(bed.available ? .green : .red) }
                            if let o = bed.occupant {
                                Text("\(o.patient_name)\(o.record_number.map { " · \($0)" } ?? "")").font(.footnote)
                                Text("Desde \(DoctorRoomText.date(o.since))").font(.caption).foregroundStyle(.secondary)
                                Button("Ver paciente hospitalizado") { openPatient(o.admission_id) }.font(.footnote.bold())
                            } else if bed.state == "ocupada" {
                                Text("Ocupada por un paciente de otro médico.").font(.caption).foregroundStyle(.secondary)
                            }
                            if bed.available {
                                Button("Hospitalizar paciente aquí") { hospitalize(bed) }.buttonStyle(.borderedProminent).tint(HospitalTheme.wine).controlSize(.small)
                            }
                        }.padding(.vertical, 4)
                    }
                    if room.beds.isEmpty { Text("Sin camas registradas.").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(room.code).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() } } }
        }
    }
    private func row(_ k: String, _ v: String) -> some View { HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v) } }
}

// MARK: - Paciente hospitalizado + alta

struct DoctorHospitalizedSheet: View {
    let patient: DoctorHospitalized
    @ObservedObject var model: DoctorRoomsModel
    @State private var notes = ""
    @State private var confirm = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Paciente") {
                    row("Nombre", patient.patient_name); row("Expediente", patient.record_number ?? "—")
                    row("Estado", DoctorAdmissionLabels.status(patient.status)); row("Prioridad", patient.priority.capitalized)
                }
                Section("Ubicación") {
                    row("Habitación", patient.room ?? "Sin asignar"); row("Cama", patient.bed ?? "—"); row("Piso", patient.floor ?? "—")
                    row("Categoría", DoctorAdmissionLabels.category(patient.category)); row("Ingreso", DoctorRoomText.date(patient.assigned_at ?? patient.ordered_at))
                }
                Section("Motivo clínico") {
                    Text(patient.reason)
                    if let o = patient.observations { Text(o).font(.footnote).foregroundStyle(.secondary) }
                }
                if patient.status == "hospitalizado" {
                    Section("Dar de alta") {
                        TextField("Indicaciones de alta (obligatorio)", text: $notes, axis: .vertical).lineLimit(3...8)
                        Button(role: .destructive) { confirm = true } label: {
                            HStack { if model.saving { ProgressView() }; Text("Registrar alta médica") }
                        }.disabled(model.saving || notes.trimmingCharacters(in: .whitespacesAndNewlines).count < 5)
                    }
                } else if patient.status == "alta_medica" {
                    Section("Alta médica") {
                        row("Fecha", DoctorRoomText.date(patient.discharged_at))
                        if let n = patient.discharge_notes { Text(n).font(.footnote) }
                        Text("Pendiente de que recepción libere la cama.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error = model.error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Hospitalización").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() } } }
            .confirmationDialog("¿Dar de alta a \(patient.patient_name)?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Dar de alta", role: .destructive) { Task { if await model.discharge(patient.admission_id, name: patient.patient_name, notes: notes) { dismiss() } } }
            }
        }
    }
    private func row(_ k: String, _ v: String) -> some View { HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v).multilineTextAlignment(.trailing) } }
}

// MARK: - Hospitalizar (buscar paciente atendido)

struct DoctorHospitalizeSheet: View {
    let bed: DoctorRoomBed
    @ObservedObject var model: DoctorRoomsModel
    @State private var query = ""
    @State private var selected: DoctorRoomCandidate?
    @State private var reason = ""
    @State private var instructions = ""
    @State private var urgent = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Cama seleccionada") { Text("Cama \(bed.code)").bold() }
                Section {
                    TextField("Buscar por nombre, expediente o DUI", text: $query).textInputAutocapitalization(.never)
                    ForEach(model.candidates) { c in
                        Button { if c.active_admission == nil { selected = c } } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(c.full_name).foregroundStyle(HospitalTheme.ink)
                                    Text([c.record_number, c.last_consultation.map { "Última consulta \(DoctorRoomText.date($0))" }].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                    if let a = c.active_admission { Text("Ya tiene hospitalización activa (\(DoctorAdmissionLabels.status(a)))").font(.caption).foregroundStyle(.red) }
                                }
                                Spacer()
                                if selected?.id == c.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(HospitalTheme.wine) }
                            }
                        }.disabled(c.active_admission != nil)
                    }
                    if model.candidates.isEmpty { Text("Sin pacientes que hayan pasado consulta contigo con ese criterio.").font(.caption).foregroundStyle(.secondary) }
                } header: { Text("Paciente (ya atendido por ti)") }
                Section("Datos clínicos") {
                    TextField("Motivo de hospitalización", text: $reason, axis: .vertical).lineLimit(2...6)
                    TextField("Indicaciones (opcional)", text: $instructions, axis: .vertical).lineLimit(2...6)
                    Toggle("Urgente", isOn: $urgent).tint(HospitalTheme.wine)
                }
                if let error = model.error { Text(error).foregroundStyle(.red).font(.footnote) }
                Button {
                    guard let selected else { return }
                    Task { if await model.hospitalize(patient: selected, bed: bed, reason: reason, instructions: instructions, urgent: urgent) { dismiss() } }
                } label: { HStack { if model.saving { ProgressView() }; Text("Hospitalizar") }.frame(maxWidth: .infinity) }
                    .disabled(selected == nil || reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 5 || model.saving)
            }
            .navigationTitle("Hospitalizar").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
            .task(id: query) {
                try? await Task.sleep(nanoseconds: 300_000_000)   // debounce
                guard !Task.isCancelled else { return }
                await model.search(query)
            }
        }
    }
}

// MARK: - Asignar cama a solicitud pendiente

struct DoctorAssignBedSheet: View {
    let admission: DoctorHospitalized
    @ObservedObject var model: DoctorRoomsModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Solicitud") {
                    Text(admission.patient_name).bold()
                    Text("Categoría: \(DoctorAdmissionLabels.category(admission.category))").font(.footnote)
                }
                Section("Camas libres (solo se muestran las desocupadas)") {
                    let beds = model.freeBeds(kind: admission.category)
                    ForEach(beds, id: \.1.id) { pair in
                        Button {
                            Task { if await model.assign(admission, bed: pair.1) { dismiss() } }
                        } label: { HStack { Text("\(pair.0.code) · Cama \(pair.1.code)"); Spacer(); Text(pair.0.floor).font(.caption).foregroundStyle(.secondary) } }
                            .disabled(model.saving)
                    }
                    if beds.isEmpty { Text("No hay camas libres de esta categoría.").foregroundStyle(.secondary) }
                }
                if let error = model.error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Asignar cama").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
    }
}
