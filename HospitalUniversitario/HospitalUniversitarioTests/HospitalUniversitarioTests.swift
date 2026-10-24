//
//  HospitalUniversitarioTests.swift
//  HospitalUniversitarioTests
//
//  Created by ESTUDIANTE on 17/10/26.
//

import Testing
import Foundation
@testable import HospitalUniversitario

struct HospitalUniversitarioTests {

    @Test func allExportedScreensAreInBundle() throws {
        let catalog = try ScreenCatalog.load()
        #expect(catalog["patient"]?.count == 11)
        #expect(catalog["doctor"]?.count == 10)
        #expect(catalog["patient"]?.first?.id == "home")
        #expect(catalog["doctor"]?.first?.id == "home")
        #expect(catalog["patient"]?.first(where: { $0.id == "turns" })?.layout == "queue")
        #expect(catalog["doctor"]?.first(where: { $0.id == "turns" })?.layout == "schedule")
    }

    @Test func queueStatusDoesNotRequireAnEstimatedWaitOrRoom() throws {
        let data = Data(#"{"ticket_id":"00000000-0000-4000-8000-000000000001","number":14,"status":"waiting","people_ahead":2,"display_number":"A-014","serving_number":null,"consultation_room":null,"estimated_wait_minutes":null}"#.utf8)
        let status = try JSONDecoder().decode(QueueStatus.self, from: data)
        #expect(status.display_number == "A-014")
        #expect(status.people_ahead == 2)
        #expect(status.consultation_room == nil)
        #expect(status.estimated_wait_minutes == nil)
    }

    @Test @MainActor func sharedPolicyLoadsFromAppBundle() throws {
        let core = try SharedCore()
        let allowed = Data(#"{"profile":{"status":"active"},"roles":[{"code":"doctor"}],"staff_id":"00000000-0000-4000-8000-000000000001","patient_id":null}"#.utf8)
        let suspended = Data(#"{"profile":{"status":"suspended"},"roles":[{"code":"doctor"}],"staff_id":"00000000-0000-4000-8000-000000000001"}"#.utf8)
        #expect(try core.roles(allowed) == ["doctor"])
        #expect(try core.roles(suspended).isEmpty)
        #expect(try core.turnResource("patient") == "queue_tickets")
        #expect(try core.turnResource("doctor") == "staff_shifts")
    }

    @Test @MainActor func patientQueriesAlwaysIncludeOwner() throws {
        let owner = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let core = try SharedCore()
        let data = try core.request(resource: "queue_tickets", cursor: nil, owner: owner)
        let request = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let filters = try #require(request["p_filters"] as? [[String: Any]])
        #expect(filters.first?["column"] as? String == "patient_id")
        #expect(filters.first?["value"] as? String == owner.uuidString)
    }

    @Test func nullableTicketFieldsDecode() throws {
        let data = Data(#"{"data":[{"id":"00000000-0000-4000-8000-000000000001","queue_id":"00000000-0000-4000-8000-000000000002","patient_id":"00000000-0000-4000-8000-000000000003","triage_level_id":null,"number":7,"status":"waiting","arrived_at":"2026-10-23T07:00:00-06:00","called_at":null,"started_at":null,"finished_at":null,"created_at":"2026-10-23T07:00:00-06:00","updated_at":"2026-10-23T07:00:00-06:00","row_version":1}],"has_more":false,"next_cursor":null}"#.utf8)
        let page = try JSONDecoder().decode(ResourcePage<QueueTicket>.self, from: data)
        #expect(page.data.first?.number == 7)
        #expect(page.data.first?.called_at == nil)
        #expect(!page.has_more)
    }

}
