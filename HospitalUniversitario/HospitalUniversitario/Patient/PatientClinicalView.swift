import SwiftUI

/// Solo lectura. Recibe exclusivamente las páginas autorizadas de la sesión del Paciente.
struct PatientClinicalView: View {
    @ObservedObject var model: MobileModuleViewModel
    @ObservedObject var laboratory: MobileModuleViewModel
    let module: String
    let profile: UserProfile?
    let navigate: (String) -> Void
    @State private var selectedID: UUID?
    @Environment(\.openURL) private var openURL
    private var source: MobileModuleViewModel { module == "laboratory" ? model : laboratory }
    private var studies: [MobileItem] { source.items.sorted { (DoctorDate.parse($0.event_at) ?? .distantPast) > (DoctorDate.parse($1.event_at) ?? .distantPast) } }
    private var selected: MobileItem? { studies.first { $0.id == selectedID } }
    private func field(_ label: String) -> String? { model.page?.sections.flatMap(\.fields).first { $0.label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }?.value }
    private var name: String { field("Nombre") ?? profile?.fullName ?? "No hay datos reales" }
    private var age: String { field("Edad") ?? "No hay datos reales" }
    private var phone: String { field("Teléfono") ?? profile?.contacts.first { $0.kind == "phone" }?.value ?? "No hay datos reales" }
    private func state(_ item: MobileItem) -> String { ["pending":"Pendiente", "in_progress":"En Proceso", "processing":"En Proceso", "released":"Completado", "completed":"Completado", "cancelled":"Cancelado"][item.status] ?? "Estado no disponible" }
    private func released(_ item: MobileItem) -> Bool { ["released", "completed"].contains(item.status) }
    @ViewBuilder private func badge(_ item: MobileItem) -> some View {
        if released(item) { ClinicalLabStateBadge(state: .completed) }
        else if item.status == "pending" { ClinicalLabStateBadge(state: .pending) }
        else if ["in_progress", "processing"].contains(item.status) { ClinicalLabStateBadge(state: .processing) }
        else { HospitalBadge(text: state(item), warning: true) }
    }
    private func detail(_ item: MobileItem, _ label: String) -> String { DoctorConsultationFields.value(item.details.first { $0.label.localizedCaseInsensitiveCompare(label) == .orderedSame }?.value) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.loading { ProgressView("Cargando tu información") }
            if let error = model.error { Text(error).font(.footnote); Button("Reintentar") { Task { await model.load(module) } } }
            if model.page != nil {
                VStack(spacing: 22) {
                    HStack {
                        Button("Volver") { if selectedID != nil { selectedID = nil } else { navigate("home") } }.font(.subheadline.weight(.semibold)).tint(HospitalTheme.wine)
                        Spacer(); Text("ACCESO PERSONAL").font(.caption2.weight(.bold)).foregroundStyle(HospitalTheme.secondary)
                    }
                    if let item = selected { examTicket(item) }
                    else {
                        Image(systemName: module == "chart" ? "checkmark" : "testtube.2").font(.system(size: 34, weight: .bold)).foregroundStyle(.white).frame(width: 82, height: 82).background(HospitalTheme.wine, in: Circle())
                        Text(module == "chart" ? "Mi expediente" : "Mis laboratorios").font(.system(size: 27, weight: .bold))
                        Text("Tu información médica · Solo lectura").font(.caption).foregroundStyle(HospitalTheme.secondary)
                        if module == "chart" {
                            personalCard(full: true)
                            ForEach(Array((model.page?.sections ?? []).enumerated()), id: \.offset) { _, section in
                                PatientFormCard(titulo: section.title, icono: "doc.text") {
                                    if section.fields.isEmpty { Text("Sin registros publicados.").font(.footnote).foregroundStyle(HospitalTheme.secondary) }
                                    ForEach(Array(section.fields.enumerated()), id: \.offset) { _, value in DoctorConsultationField(label: value.label, value: DoctorConsultationFields.value(value.value)) }
                                }
                            }
                            ForEach(model.items) { item in
                                PatientFormCard(titulo: item.title, icono: "doc") {
                                    Text(DoctorDate.display(item.event_at)).font(.caption)
                                    ForEach(Array(item.details.enumerated()), id: \.offset) { _, value in DoctorConsultationField(label: value.label, value: value.value) }
                                    if let id = item.document_id { Button("Abrir documento") { Task { if let url = await model.documentURL(id) { openURL(url) } } } }
                                }
                            }
                            if model.page?.has_more == true { Button("Cargar más documentos") { Task { await model.load(module, more: true) } } }
                        }
                        laboratoryList
                    }
                }.padding(20).frame(maxWidth: .infinity).background(.white, in: RoundedRectangle(cornerRadius: 24)).overlay(RoundedRectangle(cornerRadius: 24).stroke(HospitalTheme.rose, lineWidth: 1))
            }
        }.onChange(of: module) { _, _ in selectedID = nil }
    }
    @ViewBuilder private func personalCard(full: Bool) -> some View {
        if full {
            PatientFormCard(titulo: "Datos personales", icono: "person") {
                ClinicalPatientIdentityView(givenName: profile?.person?.given_names ?? field("Nombres") ?? "", familyName: profile?.person?.family_names ?? field("Apellido") ?? "", fullName: name, age: age, dui: field("DUI") ?? "", email: profile?.auth_email ?? "", phone: phone, record: field("Expediente") ?? "")
            }
        } else {
            PatientFormCard(titulo: "Paciente", icono: "person.crop.circle") {
                HStack(spacing: 14) {
                    Text(name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined()).font(.title2.weight(.bold)).foregroundStyle(.white).frame(width: 58, height: 58).background(HospitalTheme.wine, in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Nombre completo").font(.caption.weight(.semibold)).foregroundStyle(HospitalTheme.secondary)
                        Text(name).font(.system(size: 18, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack { DoctorConsultationField(label: "Edad", value: age); DoctorConsultationField(label: "Teléfono", value: phone) }.padding(14).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
    private var laboratoryList: some View {
        PatientFormCard(titulo: "Laboratorios del expediente", icono: "testtube.2") {
            Text("Más recientes primero · Solicitudes y resultados del paciente").font(.caption).foregroundStyle(HospitalTheme.secondary)
            if source.loading { ProgressView() }
            if let error = source.error { Text(error).font(.footnote); Button("Reintentar laboratorios") { Task { await source.load("laboratory") } } }
            if studies.isEmpty && !source.loading && source.error == nil { Text("Todavía no tienes exámenes registrados.").font(.footnote) }
            ForEach(studies) { item in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 14) {
                        if let date = DoctorDate.parse(item.event_at) {
                            VStack(spacing: 3) { Text(date.formatted(.dateTime.day())).font(.title2.weight(.bold)); Text(date.formatted(.dateTime.month(.abbreviated))).font(.caption.weight(.semibold)) }
                                .foregroundStyle(HospitalTheme.wine).frame(width: 55, height: 62).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 14))
                        }
                        VStack(alignment: .leading, spacing: 7) { Text(item.title).font(.subheadline.weight(.bold)); Text(DoctorDate.display(item.event_at)).font(.caption).foregroundStyle(HospitalTheme.secondary) }
                        Spacer(minLength: 0)
                    }
                    badge(item)
                    Text(released(item) ? "Resultado disponible para revisión" : item.status == "pending" ? "Solicitud pendiente de procesamiento" : item.status == "cancelled" ? "Solicitud cancelada" : "El laboratorio está procesando el examen").font(.footnote).foregroundStyle(HospitalTheme.secondary)
                    Divider().overlay(HospitalTheme.rose)
                    Button { selectedID = item.id } label: { HStack { Text("Ver detalle"); Spacer(); Image(systemName: "arrow.up.right") } }.font(.subheadline.weight(.semibold)).tint(HospitalTheme.wine)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(HospitalTheme.rose, lineWidth: 1)).overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 3).fill(HospitalTheme.wine).frame(width: 3).padding(.vertical, 20) }
            }
            Button("Actualizar laboratorios") { Task { await source.load("laboratory") } }.font(.caption.weight(.semibold)).tint(HospitalTheme.wine)
            if source.page?.has_more == true { Button("Cargar más laboratorios") { Task { await source.load("laboratory", more: true) } } }
        }
    }
    @ViewBuilder private func examTicket(_ item: MobileItem) -> some View {
        Text("Detalle de examen").font(.system(size: 27, weight: .bold))
        personalCard(full: false)
        PatientFormCard(titulo: "Información del examen", icono: "testtube.2") {
            Text(item.title).font(.title3.weight(.bold)); badge(item)
            Text(DoctorDate.display(item.event_at)).font(.subheadline.weight(.semibold)).padding(16).frame(maxWidth: .infinity).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 14))
            DoctorConsultationField(label: "Motivo del examen", value: detail(item, "Indicaciones"))
        }
        PatientFormCard(titulo: "Resultado del examen", icono: "doc.text.magnifyingglass") {
            if released(item) {
                ForEach(Array(item.details.filter { $0.label != "Indicaciones" }.enumerated()), id: \.offset) { _, value in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(value.label).font(.subheadline.weight(.semibold))
                        Text(DoctorConsultationFields.value(value.value)).font(.title3.weight(.bold)).foregroundStyle(HospitalTheme.wine).fixedSize(horizontal: false, vertical: true)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(HospitalTheme.rose, in: RoundedRectangle(cornerRadius: 14))
                }
                if item.details.isEmpty { Text("No hay un informe publicado todavía.").font(.footnote) }
                if let id = item.document_id { Button("Abrir documento") { Task { if let url = await source.documentURL(id) { openURL(url) } } } }
            } else {
                Text(state(item)).font(.title3.weight(.bold))
                Text("Los resultados aparecerán aquí cuando el laboratorio los publique.").font(.subheadline).foregroundStyle(HospitalTheme.secondary)
            }
        }
        Button("Volver") { selectedID = nil }.buttonStyle(HospitalPrimaryButtonStyle())
    }
}
