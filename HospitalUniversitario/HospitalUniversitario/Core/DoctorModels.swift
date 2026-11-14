import Foundation

enum DoctorAdmissionLabels {
    static func category(_ value: String) -> String { value == "vip" ? "VIP" : value == "semiprivada" ? "Semiprivada" : value }
    static func status(_ value: String) -> String {
        ["solicitado":"Pendiente de recepción", "asignado":"Asignado", "hospitalizado":"Ingresado", "alta_medica":"Alta médica", "cerrado":"Cerrado", "cancelado":"Cancelado", "rechazada":"Rechazada", "cancelada":"Cancelada"][value] ?? value
    }
}
struct DoctorAdmission: Decodable, Identifiable, Sendable {
    struct Assignment: Decodable, Sendable { let room: String; let bed: String; let floor: String; let assigned_at: String; let released_at: String? }
    struct Event: Decodable, Sendable { let status: String; let decision: String?; let reason: String?; let at: String }
    let id: UUID
    let patient_id: UUID
    let patient_name: String
    let record_number: String?
    let doctor_name: String
    let category: String
    let reason: String
    let observations: String?
    let priority: String
    let status: String
    let ordered_at: String
    let encounter_id: UUID?
    let decision: String?
    let decision_reason: String?
    let assignment: Assignment?
    let history: [Event]
}
struct DoctorAdmissionsPage: Decodable, Sendable {
    let items: [DoctorAdmission]
    let total: Int
    let has_more: Bool
    let next_offset: Int?
    let doctor_name: String
    let categories: [String]
    let priorities: [String]
}
struct DoctorAdmissionInput: Sendable {
    let patient: UUID
    let patientName: String
    let recordNumber: String?
    let encounter: UUID?
    let category: String
    let priority: String
    let reason: String
    let observations: String
    let key: UUID
}

enum DoctorJSON: Codable, Sendable, Equatable {
    case string(String), number(Int), decimal(Decimal), bool(Bool), object([String: DoctorJSON]), array([DoctorJSON]), null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let item = try? value.decode(Bool.self) { self = .bool(item) }
        else if let item = try? value.decode(Int.self) { self = .number(item) }
        else if let item = try? value.decode(Decimal.self) { self = .decimal(item) }
        else if let item = try? value.decode(String.self) { self = .string(item) }
        else if let item = try? value.decode([String: DoctorJSON].self) { self = .object(item) }
        else { self = .array(try value.decode([DoctorJSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .string(let item): try value.encode(item)
        case .number(let item): try value.encode(item)
        case .decimal(let item): try value.encode(item)
        case .bool(let item): try value.encode(item)
        case .object(let item): try value.encode(item)
        case .array(let item): try value.encode(item)
        case .null: try value.encodeNil()
        }
    }
}

enum DoctorDate {
    static func parse(_ value: String) -> Date? {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    static func display(_ value: String?) -> String {
        guard let value, let date = parse(value) else { return "No disponible" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
    static func timestamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}

struct DoctorWorkspace: Codable, Sendable {
    struct Statistics: Codable, Sendable {
        let consultations: Int
        let completed_consultations: Int
        let issued_orders: Int
        let pending_orders: Int
    }
    let doctor_name: String
    let facility_name: String
    let appointments: [DoctorAppointment]
    let orders: [DoctorLabOrder]
    let tests: [DoctorLabTest]
    let notifications: [DoctorNotification]
    let stats: Statistics
    var medications: [DoctorMedication]? = nil
}

struct DoctorAppointment: Codable, Identifiable, Sendable {
    let id: UUID
    let patient_id: UUID
    let patient_name: String
    let record_number: String
    let phone: String?
    let ticket_number: String?
    let period: String
    let status: String
    let encounter_id: UUID?
    var age: Int? = nil
    var reason: String? = nil
    var symptoms: [String]? = nil
    var other_symptoms: String? = nil
    var specialty: String? = nil
    var room_code: String? = nil
    var duration_minutes: Int? = nil
    var startDate: Date? {
        guard let first = period.dropFirst().split(separator: ",", maxSplits: 1).first else { return nil }
        let clean=String(first).trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            .replacingOccurrences(of: " ", with: "T")
            .replacingOccurrences(of: "([+-]\\d{2})$", with: "$1:00", options: .regularExpression)
        return DoctorDate.parse(clean)
    }
}

struct DoctorLabTest: Codable, Identifiable, Sendable {
    let id: Int64
    let code: String
    let name: String
    var category: String? = nil
}
struct DoctorLabSelection: Sendable {
    let encounter: UUID
    let patientName: String
    let recordNumber: String?
    let tests: [Int64]
    let reason: String
    let key: UUID
}
struct DoctorLabParameter: Decodable {
    let label: String
    let value: String?
    let unit: String?
    let reference: String?
    let observation: String?
}

struct DoctorDiagnosis: Codable, Identifiable, Sendable {
    let id: UUID
    let code: String
    let description: String
}

struct DoctorAssignedPatient: Codable, Identifiable, Sendable {
    let id: UUID
    let full_name: String
    let record_number: String?
    let dui: String?
    let email: String?
    let phone: String?
    let birth_date: String?
    let age: Int?
    let active_encounter_id: UUID?
    var initials: String { full_name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased() }
}
struct DoctorPatientDirectoryPage: Decodable {
    let patients: [DoctorAssignedPatient]
    let total: Int
    let has_more: Bool
    let next_offset: Int?
}
struct DoctorPatientLab: Decodable, Identifiable {
    let id: UUID
    let test_name: String
    let reason: String
    let status: String
    let ordered_at: String
    let result_summary: String?
    let completed_at: String?
    var patient_name: String? = nil
    var record_number: String? = nil
    var parameters: [DoctorLabParameter]? = nil
    var published_at: String? = nil
}
struct DoctorPatientLabPage: Decodable {
    let items: [DoctorPatientLab]
    let total: Int
    let has_more: Bool
    let next_offset: Int?
}

struct DoctorLabOrder: Codable, Identifiable, Sendable {
    let id: UUID
    let patient_id: UUID
    let patient_name: String
    let ticket_number: String?
    let phone: String?
    let test_name: String
    let issued_at: String?
    let facility_name: String
    let doctor_name: String
    let instructions: String?
    let status: String
    let row_version: Int
    var result_summary: String? = nil
}

struct DoctorNotification: Codable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let body: String
    let created_at: String
    let read_at: String?
    let row_version: Int
}

struct DoctorPatientChart: Codable, Sendable {
    struct Patient: Codable, Identifiable, Sendable {
        let id: UUID
        let full_name: String
        let record_number: String
        let birth_date: String?
        let sex: String?
        let phone: String?
        let email: String?
        let address: String?
        let identification: String?
    }
    let patient: Patient
    let allergies: [String]
    let conditions: [String]
    let history: [DoctorConsultation]
    var blood_type: String? = nil
    var medical_history: [String]? = nil
    var medications: [String]? = nil
    var vitals: [Vital]? = nil
    var prescriptions: [DoctorIssuedPrescription]? = nil

    struct Vital: Codable, Sendable {
        let label: String
        let value: String
    }
}

struct DoctorConsultation: Codable, Identifiable, Sendable {
    let id: UUID
    let started_at: String
    let status: String
    let subjective: String?
    let objective: String?
    let assessment: String?
    let plan: String?
    let note_id: UUID?
    let note_version: Int?
    let row_version: Int
    var diagnosis_code: String? = nil
    var vitals: [String: String]? = nil
}

struct DoctorConsultationDraft: Equatable, Sendable {
    var subjective = ""
    var objective = ""
    var assessment = ""
    var plan = ""
    var diagnosis_code = ""
    var vitals: [String: String] = [:]
    var canSave: Bool { [subjective,objective,assessment,plan].allSatisfy { $0.count <= 10000 } && diagnosis_code.count <= 50 }
    var isValid: Bool {
        [subjective, objective, assessment, plan].allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 10000
        }
    }
    var values: [String: DoctorJSON] {
        ["subjective": .string(subjective), "objective": .string(objective),
         "assessment": .string(assessment), "plan": .string(plan), "diagnosis_code": .string(diagnosis_code),
         "vitals": .object(vitals.mapValues { .string($0.replacingOccurrences(of: ",", with: ".")) })]
    }
}

struct DoctorMedication: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let strength: String?
    let presentation: String?
    var label: String { [name,strength,presentation].compactMap { $0 }.joined(separator: " · ") }
}
struct DoctorIssuedPrescription: Codable, Identifiable, Sendable {
    let id: UUID
    let code: String
    let issued_at: String
    let status: String
    let lines: [String]
}
struct DoctorRxLine: Identifiable, Sendable {
    let id = UUID()
    let medication: DoctorMedication
    let dose: Decimal
    let unit: String
    let frequency: Int
    let route: String
    let quantity: Int
    let days: Int
    let instructions: String
    var values: DoctorJSON { .object(["medication_id":.string(medication.id.uuidString),"dose":.decimal(dose),
        "dose_unit":.string(unit),"frequency_hours":.number(frequency),"route":.string(route),
        "quantity":.number(quantity),"duration_days":.number(days),"observations":.string(instructions)]) }
}
