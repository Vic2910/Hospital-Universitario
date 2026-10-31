import SwiftUI

/// Normalización de campos opcionales compartida por listado y ticket.
enum DoctorConsultationFields {
    static let missing = "No hay datos reales"
    static func value(_ text: String?) -> String {
        let clean = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return clean.isEmpty ? missing : clean
    }
    static func age(_ age: Int?) -> String { age.map { $0 >= 0 ? "\($0) años" : missing } ?? missing }
    static func symptoms(_ values: [String]?) -> String {
        let clean = (values ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return clean.isEmpty ? missing : clean.joined(separator: ", ")
    }
    static func time(_ text: String) -> String {
        text.isEmpty || text == "Horario no disponible" || text == "Horario de ejemplo" ? missing : text
    }
    static func status(_ value: String) -> String {
        ["confirmed": "Confirmada", "scheduled": "Programada", "checked_in": "En espera", "in_progress": "En curso", "completed": "Finalizada", "cancelled": "Cancelada"][value] ?? "Pendiente"
    }
}

struct DoctorConsultationField: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(HospitalTheme.secondary)
            Text(value).font(.subheadline).foregroundStyle(HospitalTheme.ink).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}

/// Hoja del ticket seleccionada desde la agenda real o local, sin una ruta nueva.
struct DoctorConsultationTicketView: View {
    let appointment: DoctorAppointment
    let day: Date
    let time: String
    let demonstration: Bool
    let close: () -> Void
    var openCare: (() -> Void)? = nil
    var embedded = false
    var closeLabel = "Volver a consultas"
    var context: [MobileField] = []
    private let referenceBlue = Color(red: 33/255, green: 150/255, blue: 243/255)

    var body: some View {
        Group { if embedded { ticketContent } else { ScrollView { ticketContent } } }.background(HospitalTheme.background)
    }
    private var ticketContent: some View {
            VStack(spacing: 22) {
                Image(systemName: "checkmark").font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 82, height: 82).background(HospitalTheme.wine, in: Circle()).accessibilityHidden(true)
                Text("Detalle de consulta").font(.system(size: 27, weight: .bold)).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(demonstration ? "Datos de ejemplo · Sin reserva real" : DoctorConsultationFields.status(appointment.status))
                    .font(.footnote).foregroundStyle(HospitalTheme.secondary)
                VStack(spacing: 8) {
                    Text("Fecha y hora").font(.caption).foregroundStyle(HospitalTheme.secondary)
                    Text(DoctorConsultationFields.time(time) == DoctorConsultationFields.missing ? DoctorConsultationFields.missing : day.formatted(.dateTime.locale(Locale(identifier: "es_GT")).weekday(.wide).day().month(.wide).year()))
                    Text(DoctorConsultationFields.time(time))
                }.font(.headline).multilineTextAlignment(.center).padding(18).frame(maxWidth: .infinity)
                    .background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 18) {
                    DoctorConsultationField(label: "Paciente", value: DoctorConsultationFields.value(appointment.patient_name))
                    HStack(alignment: .top, spacing: 16) {
                        DoctorConsultationField(label: "Edad", value: DoctorConsultationFields.age(appointment.age))
                        DoctorConsultationField(label: "Teléfono", value: DoctorConsultationFields.value(appointment.phone))
                    }
                    Divider()
                    DoctorConsultationField(label: "Motivo de la consulta", value: DoctorConsultationFields.value(appointment.reason))
                    DoctorConsultationField(label: "Síntomas", value: DoctorConsultationFields.symptoms(appointment.symptoms))
                }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 16))
                ForEach(Array(context.enumerated()), id: \.offset) { _, field in DoctorConsultationField(label: field.label, value: field.value) }
                if let openCare { Button("Abrir atención", action: openCare).font(.subheadline.weight(.semibold)).tint(HospitalTheme.wine) }
                Button(action: close) {
                    Text(closeLabel).font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 54)
                        .background(referenceBlue, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }.padding(22).foregroundStyle(HospitalTheme.ink)
    }
}
