import Foundation
import Testing
@testable import HospitalUniversitario

struct MobileModuleTests {
    @Test func prescriptionPayloadKeepsDecimalAndExplicitNullWithoutClientID() throws {
        let line = PrescriptionLine(medication_id: UUID(), dose: Decimal(string: "0.125")!,
            dose_unit_id: UUID(), route_id: UUID(), interval_hours: 8, instructions: "Prueba",
            starts_on: "2026-10-28", ends_on: nil, quantity: 3)
        let encoded = try JSONEncoder().encode([line])
        let rows = try #require(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        let value = try #require(rows.first)
        #expect(value["id"] == nil)
        #expect(value["ends_on"] is NSNull)
        #expect((value["dose"] as? NSNumber)?.doubleValue == 0.125)
        let parameters = try JSONDecoder().decode(DoctorJSON.self, from: encoded)
        let reencoded = try JSONEncoder().encode(parameters)
        let replay = try #require(JSONSerialization.jsonObject(with: reencoded) as? [[String: Any]])
        #expect((replay.first?["dose"] as? NSNumber)?.doubleValue == 0.125)
    }

    @Test func modulePageDecodesNullableActionsAndCompositeCursor() throws {
        let json = #"{"items":[{"id":"00000000-0000-4000-8000-000000000001","title":"Consulta","subtitle":null,"status":"closed","event_at":"2026-10-28T12:00:00Z","row_version":7,"details":[],"action":null,"document_id":null}],"sections":[],"options":[],"preferences":[],"phone":null,"emergency":null,"has_more":true,"next_cursor":{"id":"00000000-0000-4000-8000-000000000001","value":"2026-10-28T12:00:00Z"}}"#
        let page = try JSONDecoder().decode(MobileModulePage.self, from: Data(json.utf8))
        #expect(page.items.first?.row_version == 7)
        #expect(page.items.first?.action == nil)
        #expect(page.items.first?.document_id == nil)
        #expect(page.next_cursor?.value == "2026-10-28T12:00:00Z")
        #expect(page.has_more)
    }
}
