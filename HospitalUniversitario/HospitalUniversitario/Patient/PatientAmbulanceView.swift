import SwiftUI

/// Solicitud de ambulancia del paciente (RPC patient_request_ambulance / patient_ambulance_requests / patient_cancel_ambulance).
/// Concurrencia: el servidor serializa todas las solicitudes con un lock global. La app además envía una clave
/// idempotente (request_key) que se conserva entre reintentos, así un doble toque o un reintento de red no duplica.
struct PatientAmbulanceRequest: Decodable, Identifiable, Equatable {
    let id: UUID
    let status: String
    let priority: String
    let pickup_location: String
    let destination: String?
    let reason: String
    let requested_at: String
    let decision_reason: String?
    let unit: String?
    let queue_position: Int?

    var isActive: Bool { ["pendiente", "autorizada", "despachada"].contains(status) }
    var canCancel: Bool { ["pendiente", "autorizada"].contains(status) }
    var statusLabel: String {
        ["pendiente": "En espera de autorización", "autorizada": "Autorizada · asignando unidad", "despachada": "Ambulancia en camino",
         "finalizada": "Traslado finalizado", "rechazada": "Rechazada", "cancelada": "Cancelada"][status] ?? status
    }
}

struct PatientAmbulanceBoard: Decodable { let requests: [PatientAmbulanceRequest]; let units_available: Int }
struct PatientAmbulanceResult: Decodable { let id: UUID; let queue_position: Int?; let waiting: Bool?; let duplicate: Bool? }

@MainActor
final class PatientAmbulanceModel: ObservableObject {
    @Published private(set) var board: PatientAmbulanceBoard?
    @Published private(set) var loading = false
    @Published private(set) var saving = false
    @Published var error: String?
    @Published var notice: String?
    @Published var contact = ""
    @Published var phone = ""
    @Published var origin = ""
    @Published var destination = "Hospital Universitario"
    @Published var reason = ""
    @Published var urgent = true
    /// Se reutiliza en reintentos hasta que el servidor confirma; evita solicitudes duplicadas por doble toque.
    private var requestKey = UUID()
    private let api: HospitalAPI

    init(api: HospitalAPI) { self.api = api }

    var active: PatientAmbulanceRequest? { board?.requests.first { $0.isActive } }
    var formProblem: String? {
        if contact.trimmingCharacters(in: .whitespaces).isEmpty { return "Indica el nombre de contacto." }
        let digits = phone.filter(\.isNumber)
        if digits.count < 8 || digits.count > 15 { return "Ingresa un teléfono válido (8 dígitos o más)." }
        if origin.trimmingCharacters(in: .whitespaces).count < 5 { return "Describe la ubicación de recogida." }
        if reason.trimmingCharacters(in: .whitespaces).count < 5 { return "Describe brevemente el motivo." }
        return nil
    }

    func load() async {
        loading = true; defer { loading = false }
        do { board = try await api.patientAmbulance("list"); error = nil }
        catch { self.error = Self.describe(error) }
    }

    func submit() async {
        guard !saving else { return }                      // bloqueo local contra doble toque
        if let problem = formProblem { error = problem; return }
        if active != nil { error = "Ya tienes una solicitud activa."; return }
        saving = true; error = nil; notice = nil
        defer { saving = false }
        do {
            let result: PatientAmbulanceResult = try await api.patientAmbulance("request", parameters: [
                "p_contact": contact, "p_phone": phone, "p_origin": origin, "p_destination": destination,
                "p_reason": reason, "p_priority": urgent ? "urgente" : "normal", "p_key": requestKey.uuidString.lowercased()])
            requestKey = UUID()
            reason = ""
            if result.waiting == true {
                notice = "Otra solicitud llegó antes que la tuya y ocupó la unidad disponible. Tu solicitud quedó registrada en la posición \(result.queue_position ?? 1) de la cola."
            } else {
                notice = "Solicitud enviada. El hospital la autorizará y te asignará una unidad."
            }
            await load()
        } catch {
            self.error = Self.describe(error)
            if let failure = error as? HospitalError, case .message = failure { requestKey = UUID() }   // error de validación: nueva clave
            await load()                                                  // refleja lo que otro usuario cambió
        }
    }

    func cancel(_ request: PatientAmbulanceRequest) async {
        guard !saving else { return }
        saving = true; defer { saving = false }
        do {
            let _: DoctorJSON = try await api.patientAmbulance("cancel", parameters: ["p_request": request.id.uuidString.lowercased()])
            notice = "Solicitud cancelada."
        } catch { self.error = Self.describe(error) }
        await load()
    }

    static func describe(_ error: Error) -> String {
        if let failure = error as? HospitalError, case .conflict(let text) = failure { return text }
        let detail = String(describing: error)
        if detail.contains("404") || detail.contains("PGRST202") { return "La solicitud de ambulancia aún no está disponible en el servidor (migración pendiente)." }
        return error.localizedDescription
    }
}

struct PatientAmbulanceView: View {
    @StateObject private var model: PatientAmbulanceModel
    @State private var confirm = false
    let linked: Bool

    init(api: HospitalAPI, linked: Bool) {
        _model = StateObject(wrappedValue: PatientAmbulanceModel(api: api))
        self.linked = linked
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if !linked {
                card { Text("Tu cuenta aún no tiene un expediente vinculado. Acércate a recepción o llama al hospital.").font(.subheadline) }
            } else {
                if let notice = model.notice { banner(notice, icon: "checkmark.circle.fill", color: Color(red: 0.13, green: 0.5, blue: 0.3)) }
                if let error = model.error { banner(error, icon: "exclamationmark.triangle.fill", color: .red) }
                if let active = model.active { activeCard(active) } else { form }
                history
            }
        }
        .task { if linked { await model.load() } }
        .refreshable { await model.load() }
        .confirmationDialog("¿Solicitar ambulancia ahora?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Solicitar ambulancia", role: .destructive) { Task { await model.submit() } }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Si es una emergencia que pone en riesgo la vida, llama también al 911.") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AMBULANCIA", systemImage: "cross.case.fill").font(.caption2.weight(.heavy)).tracking(1.2).opacity(0.85)
            Text("Solicitar traslado").font(.title3.bold())
            if let units = model.board?.units_available {
                Text(units > 0 ? "\(units) unidad(es) disponible(s) en este momento" : "Todas las unidades están en servicio; tu solicitud quedará en cola")
                    .font(.subheadline).opacity(0.9)
            }
        }.foregroundStyle(.white).padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(HospitalTheme.wine, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var form: some View {
        card {
            Text("Datos del traslado").font(.headline)
            field("Nombre de contacto", text: $model.contact, icon: "person")
            field("Teléfono", text: $model.phone, icon: "phone").keyboardType(.phonePad)
            field("Ubicación de recogida (dirección y referencias)", text: $model.origin, icon: "mappin.and.ellipse")
            field("Destino", text: $model.destination, icon: "building.2")
            field("Motivo (síntomas, estado del paciente)", text: $model.reason, icon: "text.bubble")
            Toggle("Es urgente", isOn: $model.urgent).tint(HospitalTheme.wine)
            Button { confirm = true } label: {
                HStack { if model.saving { ProgressView().tint(.white) }; Text(model.saving ? "Enviando…" : "Solicitar ambulancia").bold() }
                    .frame(maxWidth: .infinity, minHeight: 48)
            }.buttonStyle(.borderedProminent).tint(HospitalTheme.wine)
                .disabled(model.saving || model.formProblem != nil)
            if let problem = model.formProblem { Text(problem).font(.caption).foregroundStyle(HospitalTheme.secondary) }
        }
    }

    private func activeCard(_ r: PatientAmbulanceRequest) -> some View {
        card {
            HStack { Image(systemName: r.status == "despachada" ? "car.side.fill" : "clock.fill").foregroundStyle(HospitalTheme.wine); Text(r.statusLabel).font(.headline) }
            if let position = r.queue_position { Text("Posición en cola: \(position)").font(.subheadline.weight(.semibold)) }
            if let unit = r.unit { Text("Unidad asignada: \(unit)").font(.subheadline) }
            Text("Recogida: \(r.pickup_location)").font(.footnote).foregroundStyle(HospitalTheme.secondary)
            Text("Motivo: \(r.reason)").font(.footnote).foregroundStyle(HospitalTheme.secondary)
            HStack {
                Button("Actualizar") { Task { await model.load() } }.buttonStyle(.bordered)
                if r.canCancel { Button("Cancelar solicitud", role: .destructive) { Task { await model.cancel(r) } }.buttonStyle(.bordered).disabled(model.saving) }
            }.tint(HospitalTheme.wine)
        }
    }

    @ViewBuilder private var history: some View {
        let past = model.board?.requests.filter { !$0.isActive } ?? []
        if !past.isEmpty {
            Text("Solicitudes anteriores").font(.headline)
            ForEach(past) { r in
                card {
                    Text(r.statusLabel).font(.subheadline.weight(.semibold))
                    Text(String(r.requested_at.prefix(16)).replacingOccurrences(of: "T", with: " ")).font(.caption).foregroundStyle(HospitalTheme.secondary)
                    if let reason = r.decision_reason { Text(reason).font(.caption).foregroundStyle(HospitalTheme.secondary) }
                }
            }
        } else if model.loading { ProgressView().frame(maxWidth: .infinity) }
    }

    private func field(_ title: String, text: Binding<String>, icon: String) -> some View {
        HStack { Image(systemName: icon).foregroundStyle(HospitalTheme.wine).frame(width: 22); TextField(title, text: text, axis: .vertical) }
            .padding(12).background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 12))
    }
    private func banner(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon).font(.footnote).foregroundStyle(color).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
