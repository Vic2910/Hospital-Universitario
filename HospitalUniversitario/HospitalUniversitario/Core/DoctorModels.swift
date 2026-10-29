import Foundation

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
}

struct DoctorLabTest: Codable, Identifiable, Sendable {
    let id: UUID
    let code: String
    let name: String
}

struct DoctorDiagnosis: Codable, Identifiable, Sendable {
    let id: UUID
    let code: String
    let description: String
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
}

struct DoctorConsultationDraft: Equatable, Sendable {
    var subjective = ""
    var objective = ""
    var assessment = ""
    var plan = ""
    var isValid: Bool {
        [subjective, objective, assessment, plan].allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 10000
        }
    }
    var values: [String: DoctorJSON] {
        ["subjective": .string(subjective), "objective": .string(objective),
         "assessment": .string(assessment), "plan": .string(plan)]
    }
}
