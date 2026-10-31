import Foundation
import Combine

enum ClinicalLabState: String, Codable, CaseIterable, Hashable {
    case pending = "Pendiente"
    case processing = "En Proceso"
    case completed = "Completado"
}

enum ClinicalLabCategory: String, Codable, CaseIterable, Hashable {
    case urine = "Orina", stool = "Heces", blood = "Sangre", other = "Otros"
}

struct ClinicalLabExam: Identifiable, Codable {
    let id: String
    let name: String
    let category: ClinicalLabCategory
    static let basic: [Self] = [
        .init(id: "urine", name: "Examen general de orina", category: .urine),
        .init(id: "stool", name: "Examen general de heces", category: .stool),
        .init(id: "blood", name: "Biometría hemática", category: .blood),
        .init(id: "glucose", name: "Glucosa en sangre", category: .blood),
        .init(id: "lipids", name: "Perfil lipídico", category: .blood),
        .init(id: "parasites", name: "Examen de parásitos", category: .stool),
        .init(id: "antigen", name: "Prueba rápida de antígeno", category: .other)
    ]
}

struct ClinicalLabPatient: Identifiable, Codable {
    let id: String
    let givenName: String
    let familyName: String
    let email: String
    let age: Int
    let dui: String
    let phone: String
    let record: String
    let consultationTurn: String
    var fullName: String { givenName + " " + familyName }
    var complete: Bool { age >= 0 && [givenName, familyName, email, dui, phone, record, consultationTurn].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
}

/// Snapshot local serializable, preparado para un adaptador de repositorio futuro.
struct ClinicalLabRequest: Identifiable, Codable {
    let id: UUID
    let patient: ClinicalLabPatient
    let exam: ClinicalLabExam
    let observation: String
    let doctorName: String
    let clinicName: String
    let requestedAt: Date
    let consultationTurn: String
    var state: ClinicalLabState
    var result: String?
    var weightKg: Double? = nil
    var heightCm: Double? = nil
    var requestedBy: String? = nil
    var resultValues: [ClinicalLabResultValue] = []
    var releasedAt: Date? = nil
}

struct ClinicalLabResultValue: Identifiable, Codable {
    var id: UUID = UUID()
    let name: String
    let value: String
    let unit: String
    let reference: String
}

struct ClinicalPrescriptionDetails: Codable {
    let dose: String
    let doseUnit: String
    let frequencyHours: String
    let route: String
    let durationDays: String
    let quantity: String
    static func positive(_ value: String) -> Bool {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard clean.range(of: #"^\d{1,8}(\.\d{1,4})?$"#, options: .regularExpression) != nil, let number = Double(clean) else { return false }
        return number.isFinite && number > 0
    }
    var isValid: Bool {
        Self.positive(dose) && Self.positive(frequencyHours) && Self.positive(quantity)
        && !doseUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !route.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && durationDays.range(of: #"^\d{1,5}$"#, options: .regularExpression) != nil && (Int(durationDays) ?? 0) > 0 && (Int(durationDays) ?? 0) <= 36500
    }
}

struct ClinicalRecordDesignEntry: Identifiable, Codable {
    var id: UUID = UUID()
    let patientID: String
    let requestID: UUID?
    let kind: String
    let medication: String?
    let text: String
    let authorName: String
    let authorID: String
    let createdAt: Date
    var prescription: ClinicalPrescriptionDetails? = nil
}

struct ClinicalPatientVisit: Identifiable, Codable {
    var id: UUID = UUID()
    let patientID: String
    var doctorID: String
    let date: Date
    let reason: String
    let plan: String
    let status: String
}

@MainActor
final class ClinicalLabDesignStore: ObservableObject {
    @Published var doctorName = "Dr. Luis Ramírez"
    @Published var clinicName = "Sede Central · Medicina interna"
    let ownPatientID = "p1"
    let patients: [ClinicalLabPatient] = [
        .init(id: "p1", givenName: "María", familyName: "López", email: "maria.lopez@ejemplo.test", age: 67, dui: "0123-45678", phone: "7123-4567", record: "DEMO-101", consultationTurn: "A-014"),
        .init(id: "p2", givenName: "Carlos", familyName: "Mendoza", email: "carlos.mendoza@ejemplo.test", age: 42, dui: "0234-56789", phone: "7234-5678", record: "DEMO-102", consultationTurn: "A-015"),
        .init(id: "p3", givenName: "Ana", familyName: "Reyes", email: "ana.reyes@ejemplo.test", age: 28, dui: "0345-67890", phone: "7345-6789", record: "DEMO-103", consultationTurn: "A-016")
    ]
    @Published private(set) var requests: [ClinicalLabRequest] = []
    @Published var selectedPatientID: String?
    @Published var preparing = false
    @Published var examID = ""
    @Published var weight = ""
    @Published var height = ""
    @Published var requestDate = Date()
    @Published private(set) var visits: [ClinicalPatientVisit] = []
    @Published private(set) var entries: [ClinicalRecordDesignEntry] = []
    var activeDoctorID = "doctor-demo"
    @Published var observation = ""
    @Published var confirmation: String?
    init() { reset() }
    func reset() {
        doctorName = "Dr. Luis Ramírez"; clinicName = "Sede Central · Medicina interna"; activeDoctorID = "doctor-demo"
        entries = []; weight = ""; height = ""; requestDate = Date()
        selectedPatientID = nil; preparing = false; examID = ""; observation = ""; confirmation = nil
        let today = Calendar.current.startOfDay(for: Date())
        let samples: [(String, String, Int, String, String, String)] = [
            ("p1", "doctor-demo", 0, "Consulta de seguimiento", "Seguimiento registrado en el ejemplo.", "Finalizada"),
            ("p1", "doctor-demo", -7, "Revisión de resultados", "Resultados revisados en el ejemplo.", "Finalizada"),
            ("p2", "doctor-demo", 0, "Consulta general", "Valoración registrada en el ejemplo.", "En curso"),
            ("p3", "doctor-demo", 1, "Primera consulta", "Pendiente de atención.", "Programada"),
            ("p1", "otro-doctor", 0, "Consulta ajena que debe excluirse", "No mostrar", "Finalizada")]
        visits = samples.map { .init(patientID: $0.0, doctorID: $0.1, date: Calendar.current.date(byAdding: .day, value: $0.2, to: today)!.addingTimeInterval(9 * 3600), reason: $0.3, plan: $0.4, status: $0.5) }
        let patient = patients[0]
        requests = ClinicalLabState.allCases.enumerated().map { index, state in
            ClinicalLabRequest(id: UUID(), patient: patient, exam: ClinicalLabExam.basic[index], observation: "Observación clínica de ejemplo registrada en consulta.", doctorName: doctorName, clinicName: clinicName,
                requestedAt: Calendar.current.date(byAdding: .day, value: index == 2 ? -1 : 0, to: Date())!, consultationTurn: patient.consultationTurn,
                state: state, result: state == .completed ? "Resultado de ejemplo disponible. Sin documento clínico real." : nil)
        }
        if let index = requests.firstIndex(where: { $0.state == .completed }) {
            requests[index].resultValues = [.init(name: "Hemoglobina de ejemplo", value: "13.2", unit: "g/dL", reference: "12–16 (ilustrativo)")]
            requests[index].releasedAt = requests[index].requestedAt
        }
    }
    func patient(for role: String) -> ClinicalLabPatient? { patients.first { $0.id == (role == "doctor" ? selectedPatientID : ownPatientID) } }
    func select(_ id: String) {
        weight = ""; height = ""
        selectedPatientID = id; preparing = false; examID = ""; observation = ""; confirmation = nil
    }
    func canSubmit(role: String) -> Bool {
        role == "doctor" && preparing && patient(for: role)?.complete == true && ClinicalLabExam.basic.contains { $0.id == examID }
        && !observation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && observation.count <= 2000
        && Self.measure(weight, min: 0.1, max: 500) != nil && Self.measure(height, min: 20, max: 250) != nil
        && !doctorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !clinicName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    func submit(role: String) {
        guard canSubmit(role: role), let patient = patient(for: role), let exam = ClinicalLabExam.basic.first(where: { $0.id == examID }) else { return }
        requests.insert(.init(id: UUID(), patient: patient, exam: exam, observation: observation.trimmingCharacters(in: .whitespacesAndNewlines), doctorName: doctorName, clinicName: clinicName,
            requestedAt: requestDate, consultationTurn: patient.consultationTurn, state: .pending, result: nil, weightKg: Self.measure(weight, min: 0.1, max: 500), heightCm: Self.measure(height, min: 20, max: 250), requestedBy: activeDoctorID), at: 0)
        preparing = false; examID = ""; observation = ""; confirmation = "Solicitud de ejemplo guardada para el paciente · Pendiente. No se envió al hospital."
    }
    func configureDoctor(name: String, id: String, clinic: String?) {
        let previous = activeDoctorID
        doctorName = name; activeDoctorID = id
        if let clinic { clinicName = clinic }
        for index in visits.indices where visits[index].doctorID == previous { visits[index].doctorID = id }
    }
    func ownVisits(patientID: String) -> [ClinicalPatientVisit] {
        visits.filter { $0.patientID == patientID && $0.doctorID == activeDoctorID }.sorted { $0.date > $1.date }
    }
    static func measure(_ text: String, min: Double, max: Double) -> Double? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard clean.range(of: #"^\d{1,3}(\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let value = Double(clean), value >= min, value <= max else { return nil }
        return value
    }
    func begin(role: String) {
        guard role == "doctor", patient(for: role) != nil else { return }
        weight = ""; height = ""; examID = ""; observation = ""; requestDate = Date(); preparing = true; confirmation = nil
    }
    func addEntry(role: String, kind: String, medication: String, text: String, requestID: UUID? = nil, prescription: ClinicalPrescriptionDetails? = nil) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard role == "doctor", let patient = patient(for: role), ["Observación", "Receta"].contains(kind), !clean.isEmpty, clean.count <= 2000,
            kind != "Receta" || (!medication.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && prescription?.isValid == true),
            requestID == nil || requests.contains(where: { $0.id == requestID && $0.patient.id == patient.id }) else { return false }
        entries.insert(.init(patientID: patient.id, requestID: requestID, kind: kind, medication: kind == "Receta" ? medication.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            text: clean, authorName: doctorName, authorID: activeDoctorID, createdAt: Date(), prescription: kind == "Receta" ? prescription : nil), at: 0)
        confirmation = kind == "Receta" ? "Receta local guardada · Sin emisión clínica" : "Observación local guardada"
        return true
    }
    /// Punto de entrada para un resultado publicado por un repositorio autorizado futuro.
    @discardableResult func applyPublishedResult(id: UUID, values: [ClinicalLabResultValue], narrative: String, publishedAt: Date) -> Bool {
        guard publishedAt.timeIntervalSince1970.isFinite, let index = requests.firstIndex(where: { $0.id == id }), !values.isEmpty || !narrative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if let previous = requests[index].releasedAt, publishedAt < previous { return false }
        requests[index].resultValues = values; requests[index].result = narrative; requests[index].releasedAt = publishedAt; requests[index].state = .completed
        return true
    }

}
