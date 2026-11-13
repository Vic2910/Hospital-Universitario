import Testing
import Foundation
@testable import HospitalUniversitario

/// Reglas del solicitante sin expediente. Deben coincidir con scripts/test-applicant.mjs.
/// No se ejecutaron en Windows: requieren Xcode en Mac.
@MainActor
struct ApplicantRulesTests {
    private let rules = ApplicantRules.shared

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth)) ?? Date()
    }

    private var person: ApplicantPersonalData {
        ApplicantPersonalData(given: "Ana", family: "Prueba", dui: "0123-45678",
                              birthDate: day(1995, 3, 10), phone: "7000-1111")
    }

    @Test func formatsDUIProgressively() {
        #expect(rules.formatDUI("0123456789") == "01234567-8")
        #expect(rules.formatDUI("01234") == "01234")
    }

    @Test func acceptsValidPersonalDataAndRejectsFutureBirthDate() {
        let today = day(2026, 11, 12)
        #expect(rules.validatePersonal(person, today: today) == nil)
        var future = person
        future.birthDate = day(2030, 1, 1)
        #expect(rules.validatePersonal(future, today: today) != nil)
    }

    @Test func requiresNineDUIDigits() {
        var short = person
        short.dui = "1234"
        #expect(rules.validatePersonal(short, today: day(2026, 11, 12))?.contains("9 dígitos") == true)
    }

    @Test func decodesPendingAccessWithoutPatientRole() throws {
        let data = Data(#"{"profile":{"id":"00000000-0000-4000-8000-000000000001","status":"pending"},"roles":[],"patient_id":null,"staff_id":null}"#.utf8)
        let access = try JSONDecoder().decode(HospitalAccess.self, from: data)
        #expect(access.roles.isEmpty)
        #expect(access.patient_id == nil)
    }

    @Test func phoneMatchesRegistrationBackendFormat() {
        var invalid = person
        invalid.phone = "+503 7000 1111"
        #expect(rules.validatePersonal(invalid, today: day(2026, 11, 12)) != nil)
    }

    @Test func validatesAccountCredentials() {
        let today = day(2026, 11, 12)
        #expect(rules.validateAccount(person, email: "ana@correo.test", password: "clave-segura", confirm: "clave-segura", today: today) == nil)
        #expect(rules.validateAccount(person, email: "sin-arroba", password: "clave-segura", confirm: "clave-segura", today: today) != nil)
        #expect(rules.validateAccount(person, email: "ana@correo.test", password: "corta", confirm: "corta", today: today) != nil)
        #expect(rules.validateAccount(person, email: "ana@correo.test", password: "clave-segura", confirm: "otra", today: today) != nil)
    }

    @Test func requiresPreferenceAndFutureDate() {
        let today = day(2026, 11, 12)
        var draft = ApplicantRequestDraft(specialty: "Medicina general", reason: "Control", date: day(2026, 11, 20), period: "")
        #expect(rules.validateRequest(draft, today: today) != nil)
        draft.period = "afternoon"
        #expect(rules.validateRequest(draft, today: today) == nil)
        draft.date = day(2026, 11, 1)
        #expect(rules.validateRequest(draft, today: today) != nil)
    }

    @Test func mapsInterfaceStatesFromBackendValues() {
        #expect(rules.stateView(status: "pending", appointmentStatus: nil).label == "Pendiente")
        #expect(rules.stateView(status: "identity_verified", appointmentStatus: nil).label == "En revisión")
        #expect(rules.stateView(status: "converted", appointmentStatus: nil).label == "Aceptada")
        #expect(rules.stateView(status: "converted", appointmentStatus: "scheduled").key == "scheduled")
        #expect(rules.stateView(status: "rejected", appointmentStatus: nil).label == "Rechazada")
        #expect(rules.stateView(status: "inventado", appointmentStatus: nil).label == "Estado no disponible")
    }

    @Test func stateExamplesAreMarkedAsExamplesWithoutAppointment() {
        let store = ApplicantDemoStore()
        store.addStateExamples()
        #expect(store.requests.map(\.status) == ["rejected", "cancelled"])
        #expect(store.requests.allSatisfy { $0.appointmentStatus == nil && $0.decisionReason != nil })
        #expect(rules.stateView(status: "cancelled", appointmentStatus: nil).label == "Cancelada")
    }

    @Test func submittedRequestStaysPendingWithoutAppointment() {
        let store = ApplicantDemoStore()
        let future = Date().addingTimeInterval(10 * 86400)
        let draft = ApplicantRequestDraft(specialty: "Medicina general", reason: "Control", date: future, period: "morning")
        #expect(store.submitRequest(draft) == nil)
        #expect(store.requests.count == 1)
        #expect(store.requests.first?.status == "pending")
        #expect(store.requests.first?.appointmentStatus == nil)
    }
}
