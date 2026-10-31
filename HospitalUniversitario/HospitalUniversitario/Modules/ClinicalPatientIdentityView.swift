import SwiftUI

/// Presentación única de los datos personales para Doctor y Paciente.
struct ClinicalPatientIdentityView: View {
    let givenName: String
    let familyName: String
    let fullName: String
    let age: String
    let dui: String
    let email: String
    let phone: String
    let record: String
    private var initials: String {
        let text = [givenName, familyName].compactMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) }.joined()
        return text.isEmpty ? "?" : text
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Text(initials).font(.title2.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 58, height: 58).background(HospitalTheme.wine, in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 6) {
                    Text(DoctorConsultationFields.value(fullName)).font(.system(size: 19, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                    Text("Paciente · Información registrada").font(.caption).foregroundStyle(HospitalTheme.secondary)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 18))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                ForEach([("Nombre", givenName), ("Apellido", familyName), ("Edad", age), ("DUI", dui)], id: \.0) { item in
                    DoctorConsultationField(label: item.0, value: DoctorConsultationFields.value(item.1)).padding(12).frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
                        .background(HospitalTheme.background, in: RoundedRectangle(cornerRadius: 13))
                }
            }
            ForEach([("Correo electrónico", email, "envelope"), ("Teléfono", phone, "phone"), ("Expediente", record, "doc.text")], id: \.0) { item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.2).foregroundStyle(HospitalTheme.wine).frame(width: 36, height: 36).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 11))
                    DoctorConsultationField(label: item.0, value: DoctorConsultationFields.value(item.1))
                }.padding(.vertical, 5)
            }
        }
    }
}
