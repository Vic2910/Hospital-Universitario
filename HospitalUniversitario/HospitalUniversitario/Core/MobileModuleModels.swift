import Foundation

struct MobileField: Codable, Hashable { let label: String; let value: String }
struct MobileSection: Codable { let title: String; let fields: [MobileField] }
struct MobileOption: Codable, Identifiable { let id: UUID; let name: String; let kind: String }
struct MobileItem: Codable, Identifiable {
    let id: UUID
    let title: String
    let subtitle: String?
    let status: String
    let event_at: String
    let row_version: Int
    let details: [MobileField]
    let action: String?
    let document_id: UUID?
}
struct MobilePreference: Codable, Identifiable {
    let id: UUID
    let name: String
    let enabled: Bool
    let preference_id: UUID?
    let row_version: Int?
}
struct MobileEmergency: Codable {
    let id: UUID
    let given_names: String
    let family_names: String
    let relationship: String
    let phones: [String]
    let row_version: Int
}
struct MobileModulePage: Codable {
    let items: [MobileItem]
    let sections: [MobileSection]
    let options: [MobileOption]
    let preferences: [MobilePreference]
    let phone: String?
    let emergency: MobileEmergency?
    let has_more: Bool
    let next_cursor: ResourceCursor?
}

struct PrescriptionLine: Codable, Identifiable {
    var id = UUID()
    let medication_id: UUID
    let dose: Decimal
    let dose_unit_id: UUID
    let route_id: UUID
    let interval_hours: Decimal
    let instructions: String
    let starts_on: String
    let ends_on: String?
    let quantity: Decimal

    enum CodingKeys: String, CodingKey {
        case medication_id, dose, dose_unit_id, route_id, interval_hours, instructions, starts_on, ends_on, quantity
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(medication_id, forKey: .medication_id)
        try values.encode(dose, forKey: .dose)
        try values.encode(dose_unit_id, forKey: .dose_unit_id)
        try values.encode(route_id, forKey: .route_id)
        try values.encode(interval_hours, forKey: .interval_hours)
        try values.encode(instructions, forKey: .instructions)
        try values.encode(starts_on, forKey: .starts_on)
        if let ends_on { try values.encode(ends_on, forKey: .ends_on) }
        else { try values.encodeNil(forKey: .ends_on) }
        try values.encode(quantity, forKey: .quantity)
    }
}

enum MobileFormatting {
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    static func status(_ status: String) -> String {
        ["pending":"Pendiente", "scheduled":"Programada", "confirmed":"Confirmada", "checked_in":"Registrada en recepción",
         "in_progress":"En curso", "completed":"Finalizada", "cancelled":"Cancelada", "rejected":"Rechazada",
         "open":"Abierta", "closed":"Cerrada", "issued":"Emitida", "draft":"Borrador", "released":"Publicado",
         "unread":"No leída", "read":"Leída", "ordered":"Emitida", "no_show":"No se presentó",
         "active":"Vigente", "expired":"Tratamiento finalizado"][status] ?? "Estado no disponible"
    }
}
