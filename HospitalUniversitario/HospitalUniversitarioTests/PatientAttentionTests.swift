import Foundation
import Testing
@testable import HospitalUniversitario

@MainActor
private final class AttentionStub: AttentionServing {
    var person = AttentionPerson(first_name: "Ana", last_name: "Prueba", birth_date: "1990-01-01", dui: "01234567-8", phone: "7999-0000", email: "ana@example.test")
    var submissions: [AttentionSubmission] = []
    var rows: [AttentionRequest] = []
    var failBeforeCommit = false
    var loseResponse = false
    func context() async throws -> AttentionContext {
        AttentionContext(person: person, specialties: [
            AttentionSpecialty(id: 1, name: "Especialidad de prueba asignada", available: true),
            AttentionSpecialty(id: 2, name: "Especialidad de prueba sin médico", available: false)
        ], symptoms: [AttentionSymptom(id: 1, name: "Fiebre"), AttentionSymptom(id: 2, name: "Otro")])
    }
    func requests() async throws -> [AttentionRequest] { rows }
    func submit(_ value: AttentionSubmission) async throws -> UUID {
        submissions.append(value)
        await Task.yield()
        if failBeforeCommit { throw URLError(.timedOut) }
        if !rows.contains(where: { $0.id == value.key }) {
            rows.append(AttentionRequest(id: value.key, created_at: "2026-11-13T12:00:00Z", status: "pendiente",
                specialty_name: "Especialidad de prueba asignada", reason: value.reason, preferred_period: value.period,
                symptoms: ["Fiebre"], other_symptoms: value.other, appointment_id: nil))
        }
        if loseResponse { throw URLError(.timedOut) }
        return value.key
    }
}

@MainActor
struct PatientAttentionTests {
    private func prepared(_ stub: AttentionStub) async -> PatientAttentionModel {
        let model = PatientAttentionModel(repository: stub)
        model.configure(owner: UUID()); await model.load()
        model.specialty = 1; model.selectedSymptoms = [1]; model.reason = "Motivo de prueba"
        return model
    }
    @Test func accountWithoutClinicalPatientCanSubmit() async {
        let stub = AttentionStub(); let model = await prepared(stub)
        #expect(model.canSubmit)
        await model.submit()
        #expect(stub.submissions.count == 1)
        #expect(stub.submissions.first?.missing.isEmpty == true)
        #expect(stub.submissions.first?.period == "indiferente")
        #expect(stub.submissions.first?.parameters["user_id"] == nil)
        #expect(stub.submissions.first?.parameters["patient_id"] == nil)
        #expect(model.requests.first?.status == "pendiente")
        #expect(model.confirmation != nil)
    }
    @Test func onlyMissingPersonalDataIsRequested() async {
        let stub = AttentionStub(); stub.person.phone = nil
        let model = await prepared(stub)
        #expect(!model.canSubmit)
        model.missing = ["phone": "7999-0000", "first_name": "No debe reemplazar"]
        #expect(model.canSubmit)
        await model.submit()
        #expect(stub.submissions.first?.missing == ["phone": "7999-0000"])
    }
    @Test func unavailableSpecialtyAndOtherRequireValidation() async {
        let model = await prepared(AttentionStub())
        model.specialty = 2; #expect(!model.canSubmit)
        model.specialty = 1; model.selectedSymptoms = [2]; #expect(!model.canSubmit)
        model.otherSymptoms = "Síntoma declarado"; #expect(model.canSubmit)
        model.preferredPeriod = "valor inválido"; #expect(!model.canSubmit)
    }
    @Test func doubleTapAndLostResponseDoNotDuplicate() async {
        let stub = AttentionStub(); stub.loseResponse = true
        let model = await prepared(stub)
        let first = Task { @MainActor in await model.submit() }
        let second = Task { @MainActor in await model.submit() }
        await first.value; await second.value
        #expect(stub.submissions.count == 1)
        #expect(stub.rows.count == 1)
        #expect(model.confirmation != nil)
    }
    @Test func failedTransportRetainsIdempotencyKeyAndClearsOnLogout() async {
        let stub = AttentionStub(); stub.failBeforeCommit = true
        let model = await prepared(stub)
        await model.submit(); let key = stub.submissions.first?.key
        #expect(model.error != nil)
        stub.failBeforeCommit = false; await model.submit()
        #expect(stub.submissions.last?.key == key)
        model.clear()
        #expect(model.context == nil && model.requests.isEmpty && model.missing.isEmpty)
        #expect(!model.canSubmit)
    }
}

/// Una sola solicitud activa (espejo de HospitalCore.attentionBlocker).
struct AttentionSingleRequestTests {
    private func request(_ status: String) -> AttentionRequest {
        AttentionRequest(id: UUID(), created_at: "2026-11-20T15:00:00Z", status: status, specialty_name: "Medicina general", reason: "Motivo",
            preferred_period: "manana", symptoms: ["Fiebre"], other_symptoms: nil, appointment_id: nil)
    }
    @Test func pendingRequestOrScheduledAppointmentBlocksAnotherRequest() {
        #expect(AttentionRules.blocker(requests: [request("pendiente")], scheduled: nil)?.contains("recepción la está revisando") == true)
        #expect(AttentionRules.blocker(requests: [request("en_revision")], scheduled: nil) != nil)
        #expect(AttentionRules.blocker(requests: [request("rechazada"), request("cancelada")], scheduled: nil) == nil, "Tras rechazo o cancelación puede volver a solicitar")
        let cita = ProximaCita(id: UUID(), starts_at: "2026-11-25T15:00:00Z", ends_at: "2026-11-25T15:30:00Z", status: "scheduled", doctor_name: nil)
        #expect(AttentionRules.blocker(requests: [request("agendada")], scheduled: cita)?.contains("Ya tienes una cita programada") == true)
        #expect(AttentionRules.blocker(requests: [], scheduled: nil) == nil)
    }
}

/// Turno del paciente: lo asigna el servidor (appointments.queue_number); la app solo lo presenta.
struct PatientTurnTests {
    @Test func turnIsShownWithThreeDigitsAndOnlyWhenTheServerAssignedIt() {
        let base = ProximaCita(id: UUID(), starts_at: "2026-11-25T15:00:00Z", ends_at: "2026-11-25T15:30:00Z", status: "scheduled", doctor_name: nil)
        #expect(base.turno == nil, "Sin queue_number no se inventa un turno")
        var assigned = base; assigned.queue_number = 24
        #expect(assigned.turno == "024")
        assigned.queue_number = 1234
        #expect(assigned.turno == "1234")
    }

    private func item(_ id: String, _ status: String, start: TimeInterval, end: TimeInterval?, queue: Int?) -> MobileItem {
        let now = Date()
        return MobileItem(id: UUID(uuidString: "00000000-0000-4000-8000-0000000000" + id)!, title: "Medicina general", subtitle: nil, status: status,
            event_at: DoctorDate.timestamp(now.addingTimeInterval(start)), row_version: 0, details: [], action: nil, document_id: nil,
            ends_at: end.map { DoctorDate.timestamp(now.addingTimeInterval($0)) }, queue_number: queue, queue_date: nil)
    }

    /// Misma regla que HospitalCore.patientAppointments: activa mientras no termine el horario reservado.
    @Test func activeAppointmentsFollowTheReservedEndTime() {
        let started = item("a1", "scheduled", start: -600, end: 1200, queue: 16)
        let expired = item("a2", "scheduled", start: -18000, end: -16200, queue: 3)
        let inConsultation = item("a3", "in_progress", start: -32400, end: -28800, queue: 1)
        let cancelled = item("a4", "cancelled", start: 3600, end: 5400, queue: 9)
        let completed = item("a5", "completed", start: -86400, end: -84600, queue: 4)
        let future = item("a6", "confirmed", start: 86400, end: 88200, queue: 21)
        #expect(PatientAppointmentRules.isActive(started), "Empezó pero su horario sigue vigente")
        #expect(!PatientAppointmentRules.isActive(expired), "Vencida sin atención: deja de ser activa aunque el servidor no la haya marcado")
        #expect(PatientAppointmentRules.isActive(inConsultation), "En consulta sigue activa aunque pase la hora")
        #expect(!PatientAppointmentRules.isActive(cancelled) && !PatientAppointmentRules.isActive(completed))
        let groups = PatientAppointmentRules.split([future, expired, started, cancelled, inConsultation, completed])
        #expect(groups.active.map(\.queue_number) == [1, 16, 21], "Activas de la más antigua a la más lejana")
        #expect(groups.past.map(\.queue_number) == [9, 3, 4], "Anteriores de la más reciente a la más antigua")
    }

    @Test func turnComesFromTheServerAndIsOnlyFormatted() {
        #expect(PatientAppointmentRules.turn(16) == "016")
        #expect(PatientAppointmentRules.turn(nil) == nil, "Sin queue_number no se inventa un turno")
    }
}
