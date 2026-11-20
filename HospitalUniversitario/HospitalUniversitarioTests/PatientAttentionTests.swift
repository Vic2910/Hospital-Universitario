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
