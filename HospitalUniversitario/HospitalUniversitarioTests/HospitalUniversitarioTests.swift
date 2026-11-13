import Testing
import Foundation
@testable import HospitalUniversitario

struct HospitalUniversitarioTests {
    @Test func screenCatalogLoads() throws {
        let catalog = try ScreenCatalog.load()
        #expect(catalog["patient"]?.count == 11)
        #expect(catalog["doctor"]?.count == 9)
    }
    @Test func currentPostgresModelsDecode() throws {
        let rooms = Data(#"{"data":[{"id":"00000000-0000-4000-8000-000000000001","floor_id":1,"kind":"vip","code":"VIP-301","active":true}],"has_more":false,"next_cursor":null}"#.utf8)
        let page = try JSONDecoder().decode(ResourcePage<Room>.self, from: rooms)
        #expect(page.data.first?.floor_id == 1)
        let shifts = Data(#"{"id":"00000000-0000-4000-8000-000000000001","staff_id":"00000000-0000-4000-8000-000000000001","starts_at":"2026-11-13T07:00:00Z","ends_at":"2026-11-13T15:00:00Z","shift_type":"ordinario","status":"programado"}"#.utf8)
        let shift = try JSONDecoder().decode(StaffShift.self, from: shifts)
        #expect(shift.period.contains(shift.starts_at))
    }
    @Test @MainActor func backendPlanUsesCurrentSchema() throws {
        let core = try SharedCore()
        let identity = "00000000-0000-4000-8000-000000000001"
        let context: [String: Any] = ["profile": ["id": identity], "patient_id": identity]
        let plan = try core.call("backendPlan", arguments: ["module", ["p_module": "appointments"], context]).toArray() as? [[String: Any]]
        let path = try #require(plan?.first?["path"] as? String)
        #expect(path.contains("/rest/v1/appointments?"))
        #expect(path.contains("patient_id=eq."))
    }
    @Test @MainActor func selfRegistrationCannotCreatePatient() throws {
        let core = try SharedCore()
        let identity = "00000000-0000-4000-8000-000000000001"
        let context: [String: Any] = ["profile": ["id": identity]]
        #expect(throws: (any Error).self) {
            _ = try core.call("backendPlan", arguments: ["registerPatient", [:], context])
        }
    }
    @Test @MainActor func patientHomeDoesNotRequireClinicalRecord() throws {
        let core = try SharedCore()
        let identity = "00000000-0000-4000-8000-000000000001"
        let result = try core.call("backendAccess", arguments: [
            ["id": identity], ["id": identity, "first_name": "María Elena", "last_name": "López Pérez"],
            [["user_id": identity, "role": "paciente", "active": true]], [], []
        ])
        let data = try JSONSerialization.data(withJSONObject: try #require(result.toDictionary()))
        #expect(try core.roles(data) == ["patient"])
        let access = try JSONDecoder().decode(HospitalAccess.self, from: data)
        #expect(access.profile?.greeting_name == "María López")
        #expect(access.patient_id == nil)
    }
}
