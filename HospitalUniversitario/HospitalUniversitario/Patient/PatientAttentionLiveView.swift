import SwiftUI

/// Solicitudes reales para pacientes ya vinculados. No programa citas.
@MainActor
struct PatientAttentionLiveView: View {
    @ObservedObject var model: MobileModuleViewModel
    let navigate: (String) -> Void
    let period: (String) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HospitalNotice(text: "Esta solicitud no reserva una cita. Recepción confirmará la disponibilidad.")
            if model.page != nil {
                Picker("Especialidad", selection: $model.specialty) {
                    Text("Seleccionar").tag(nil as String?)
                    ForEach(model.page?.specialties ?? []) {
                        Text($0.name).tag(Optional($0.id))
                    }
                }
                TextField("Motivo de la consulta", text: $model.reason, axis: .vertical)
                Picker("Preferencia", selection: $model.preferredPeriod) {
                    Text("Mañana").tag("manana")
                    Text("Tarde").tag("tarde")
                }
                Button("Enviar solicitud") { Task { await model.requestAppointment() } }
                    .buttonStyle(HospitalPrimaryButtonStyle())
                    .disabled(!model.canRequest || model.loading || model.saving)
            }
            MobileModuleView(model: model, module: "request", role: "patient", search: "", period: period, navigate: navigate)
        }
    }
}
