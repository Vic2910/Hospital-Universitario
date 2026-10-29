import Foundation

struct HospitalScreen: Decodable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let search: String
    let tab: String
    let layout: String
    let section: String
    let sections: [String]?
    let fields: [String]?
}

enum ScreenCatalog {
    static func load() throws -> [String: [HospitalScreen]] {
        guard let url = Bundle.main.url(forResource: "screens", withExtension: "json") else {
            throw HospitalError.message("No se encontraron las pantallas de la aplicación.")
        }
        return try JSONDecoder().decode([String: [HospitalScreen]].self, from: Data(contentsOf: url))
    }
}

struct ActivitySummary: Decodable {
    let upcoming_appointments: Int?
    let new_results: Int?
    let active_prescriptions: Int?
    let scheduled_appointments: Int?
    let waiting_patients: Int?
    let pending_prescriptions: Int?
    let tickets: [SummaryTicket]?
    struct SummaryTicket: Decodable { let id: UUID; let number: Int; let status: String }
}

struct QueueStatus: Decodable {
    struct ConsultationRoom: Decodable { let id: UUID; let name: String }
    let ticket_id: UUID
    let number: Int
    let status: String
    let people_ahead: Int
    let display_number: String?
    let serving_number: String?
    let consultation_room: ConsultationRoom?
    let estimated_wait_minutes: Int?
}

struct UserProfile: Decodable {
    struct Person: Decodable { let given_names: String; let family_names: String }
    struct Contact: Decodable { let kind: String; let value: String }
    struct Professional: Decodable { let employee_code: String; let license_number: String? }
    let person: Person?
    let auth_email: String?
    let contacts: [Contact]
    let professional: Professional?
    var fullName: String? {
        guard let person else { return nil }
        return "\(person.given_names) \(person.family_names)"
    }
}

struct HospitalOverview: Decodable {
    struct Notice: Decodable, Identifiable { let id: UUID; let title: String; let body: String }
    struct OnDuty: Decodable { let name: String; let specialty: String; let department: String }
    let capacity: Int
    let occupied: Int
    let information: [Notice]
    let on_duty: [OnDuty]
}
