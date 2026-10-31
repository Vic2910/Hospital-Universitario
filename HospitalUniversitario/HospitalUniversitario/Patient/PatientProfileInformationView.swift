import SwiftUI

/// Datos públicos del directorio oficial de UNICAES; no representan disponibilidad clínica.
enum HospitalPublicContact {
    static let address = "By pass carretera a Metapán y carretera antigua hacia San Salvador, Santa Ana, El Salvador"
    static let clinicPhone = "+503 2484-0668"
    static let source = URL(string: "https://catolica.edu.sv/contactos-facultades-y-unidades-unidaes/")!
    static let map = URL(string: "https://www.google.com/maps/search/?api=1&query=Universidad+Catolica+de+El+Salvador+Santa+Ana")!
}
struct PatientProfileCardView: View {
    let name: String
    let email: String
    let phone: String
    var demonstration = false
    private func clean(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No disponible" : value.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 14) {
                Text(name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined()).font(.system(size: 27, weight: .bold))
                    .foregroundStyle(HospitalTheme.wine).frame(width: 80, height: 80).background(.white, in: Circle())
                Text(clean(name)).font(.system(size: 23, weight: .bold)).multilineTextAlignment(.center)
                Text("Paciente · Hospital Universitario").font(.subheadline)
                if demonstration { Text("Perfil de ejemplo").font(.caption) }
            }.foregroundStyle(.white).frame(maxWidth: .infinity).padding(26).background(LinearGradient.vinoDestacado, in: RoundedRectangle(cornerRadius: 24))
            PatientFormCard(titulo: "Información personal", icono: "person.text.rectangle") {
                profileRow("Nombre completo", value: clean(name), icon: "person")
                Divider().overlay(HospitalTheme.rose)
                profileRow("Correo electrónico", value: clean(email), icon: "envelope")
                Divider().overlay(HospitalTheme.rose)
                profileRow("Teléfono", value: clean(phone), icon: "phone")
            }
            Label("Datos de tu registro", systemImage: "checkmark.shield").font(.caption).foregroundStyle(HospitalTheme.secondary)
        }
    }
    private func profileRow(_ label: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(HospitalTheme.wine).frame(width: 42, height: 42).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 13))
            DoctorConsultationField(label: label, value: value)
        }.padding(.vertical, 7)
    }
}
struct HospitalInformationView: View {
    let overview: HospitalOverview?
    let navigate: (String) -> Void
    private var examples: Bool { overview?.on_duty.isEmpty != false }
    private var specialties: [String] { examples ? PatientAppointmentView.especialidades.map(\.nombre) : Array(Set(overview!.on_duty.map(\.specialty))).sorted() }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "building.2.crop.circle.fill").font(.system(size: 38))
                Text("Tu hospital, más cerca").font(.system(size: 25, weight: .bold))
                Text("Ubicación, orientación y servicios en un solo lugar.").font(.subheadline)
                Label("Santa Ana · El Salvador", systemImage: "mappin.and.ellipse").font(.caption.weight(.semibold))
            }.foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).padding(24).background(LinearGradient.vinoDestacado, in: RoundedRectangle(cornerRadius: 24))
            PatientFormCard(titulo: "Encuéntranos", icono: "map") {
                HStack(spacing: 14) {
                    Image(systemName: "mappin.circle.fill").font(.system(size: 38)).foregroundStyle(HospitalTheme.wine)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Campus UNICAES · Santa Ana").font(.headline)
                        Text("Ubicación de referencia").font(.caption).foregroundStyle(HospitalTheme.secondary)
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 16))
                Text(HospitalPublicContact.address).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                Link(destination: HospitalPublicContact.map) { Label("Cómo llegar", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity) }.buttonStyle(HospitalPrimaryButtonStyle())
            }
            PatientFormCard(titulo: "Orientación y contacto", icono: "phone.bubble") {
                Text("¿Necesitas ayuda?").font(.title3.weight(.bold))
                DoctorConsultationField(label: "Clínica Universitaria · UNICAES", value: HospitalPublicContact.clinicPhone)
                Link(destination: URL(string: "tel:+50324840668")!) { Label("Llamar a la clínica", systemImage: "phone.fill").frame(maxWidth: .infinity) }.buttonStyle(HospitalPrimaryButtonStyle())
                HStack { Image(systemName: "bubble.left.and.bubble.right").foregroundStyle(HospitalTheme.wine); DoctorConsultationField(label: "WhatsApp institucional", value: "+503 7742-3033") }
                Link("Abrir WhatsApp institucional", destination: URL(string: "https://wa.me/50377423033")!).font(.subheadline.weight(.semibold)).tint(HospitalTheme.wine)
                Link("Ver directorio oficial de UNICAES", destination: HospitalPublicContact.source).font(.caption).tint(HospitalTheme.wine)
            }
            PatientFormCard(titulo: "Especialidades", icono: "stethoscope") {
                Text(examples ? "Catálogo de demostración" : "Especialidades de médicos publicados").font(.caption.weight(.semibold)).foregroundStyle(HospitalTheme.wine)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(specialties, id: \.self) { name in
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "cross.case").font(.title3).foregroundStyle(HospitalTheme.wine)
                            Text(name).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, minHeight: 80, alignment: .leading).padding(14).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                Text("Confirma la disponibilidad al solicitar atención.").font(.caption).foregroundStyle(HospitalTheme.secondary)
                Button("Solicitar atención") { navigate("health") }.buttonStyle(HospitalPrimaryButtonStyle())
            }
            if let overview {
                DisclosureGroup("Avisos y actividad del hospital") {
                    VStack(alignment: .leading, spacing: 14) {
                        DoctorConsultationField(label: "Ocupación general", value: "\(overview.occupied) de \(overview.capacity) camas")
                        ForEach(overview.on_duty.indices, id: \.self) { index in DoctorConsultationField(label: overview.on_duty[index].name, value: overview.on_duty[index].specialty) }
                        ForEach(overview.information) { note in DoctorConsultationField(label: note.title, value: note.body) }
                    }.padding(.vertical, 12)
                }.font(.subheadline).tint(HospitalTheme.wine)
            }
            Button("Consultar habitaciones") { navigate("rooms") }.font(.subheadline.weight(.semibold)).tint(HospitalTheme.wine)
        }
    }
}
#Preview("Perfil del Paciente") { ScrollView { PatientProfileCardView(name: "María López", email: "maria.lopez@ejemplo.test", phone: "7123-4567", demonstration: true).padding(17) } }
#Preview("Información general") { ScrollView { HospitalInformationView(overview: nil, navigate: { _ in }).padding(17) } }
