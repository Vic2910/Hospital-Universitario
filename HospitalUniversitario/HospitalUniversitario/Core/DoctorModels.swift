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

/// Traslado en ambulancia visible para el médico (RLS de public.ambulance_requests: los que solicitó y los de sus pacientes).
struct DoctorTransportRequest: Decodable, Identifiable, Sendable {
    struct Patient: Decodable, Sendable { let first_name: String?; let last_name: String? }
    let id: UUID
    let patient_id: UUID?
    let contact_name: String
    let contact_phone: String
    let pickup_location: String
    let destination: String?
    let reason: String
    let priority: String
    let status: String
    let requested_at: String
    let decision_reason: String?
    var patient: Patient? = nil
    var patientName: String? {
        let name = [patient?.first_name, patient?.last_name].compactMap { $0 }.joined(separator: " ")
        return name.isEmpty ? nil : name
    }
}
/// Estado público de la unidad (public.ambulances es legible por cualquier usuario autenticado).
struct DoctorAmbulanceUnit: Decodable, Sendable {
    let code: String
    let status: String
    let active: Bool
}
struct DoctorTransportBoard: Sendable {
    let units: [DoctorAmbulanceUnit]
    let items: [DoctorTransportRequest]
}
/// request_medical_transport: el servidor exige que el médico trate al paciente (private.treats_patient).
/// La misma clave reintenta el mismo envío sin duplicar la solicitud.
struct DoctorTransportInput: Sendable {
    let patient: UUID
    let patientName: String
    let contact: String
    let phone: String
    let origin: String
    let destination: String
    let reason: String
    let priority: String
    let key: UUID
}
enum DoctorTransportLabels {
    static func status(_ value: String) -> String {
        ["pendiente": "Pendiente de autorización", "autorizada": "Autorizada", "despachada": "Ambulancia en camino",
         "finalizada": "Finalizada", "rechazada": "Rechazada", "cancelada": "Cancelada"][value] ?? value
    }
    static func unit(_ value: String) -> String {
        ["disponible": "Disponible", "en_servicio": "En servicio", "en_mantenimiento": "En mantenimiento"][value] ?? value
    }
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
        if let date = format.date(from: value) ?? ISO8601DateFormatter().date(from: value) { return date }
        // Postgres publica microsegundos (p. ej. ended_at); se reducen a milisegundos antes de interpretar.
        let trimmed = value.replacingOccurrences(of: "(\\.\\d{3})\\d+", with: "$1", options: .regularExpression)
        return trimmed == value ? nil : format.date(from: trimmed)
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
    /// patients.patient_code; llega cuando se aplica supabase/doctor-consultation-six-fields.sql.
    var patient_code: String? = nil
    /// clinical_encounters.ended_at: hora real de finalización (misma migración). Sin ella se usa la hora de la cita.
    var finished_at: String? = nil
    var finishedDate: Date? { finished_at.flatMap(DoctorDate.parse) }
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
    /// patients.patient_code; llega cuando se aplica supabase/expedientes-historial.sql.
    var patient_code: String? = nil
    var initials: String { Self.initials(full_name) }
    static func initials(_ name: String) -> String { name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased() }
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
    /// Consulta que originó la orden (native_mobile_lab_page ya lo devuelve).
    var encounter_id: UUID? = nil
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

struct DoctorAlerts: Decodable, Sendable {
    struct Upcoming: Decodable, Sendable { let id: UUID; let starts_at: String }
    let items: [DoctorNotification]
    let unread: Int
    let has_more: Bool
    let upcoming: [Upcoming]
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
        var patient_code: String? = nil
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
    /// Llegan cuando se aplica supabase/expedientes-historial.sql; hasta entonces son nil y no se muestran.
    var ended_at: String? = nil
    var doctor_name: String? = nil
    var specialty: String? = nil
    var reason: String? = nil
    /// Síntomas que envió el paciente en su solicitud (supabase/expedientes-historial.sql). Solo lectura.
    var reported_symptoms: [String]? = nil
    var reported_other: String? = nil
}

struct DoctorConsultationDraft: Equatable, Sendable {
    var subjective = ""
    var objective = ""
    var assessment = ""
    var plan = ""
    var diagnosis_code = ""
    var vitals: [String: String] = [:]
    var canSave: Bool { [subjective,objective,assessment,plan].allSatisfy { $0.count <= 10000 } && diagnosis_code.count <= 50 }
    var isValid: Bool { missingSections.isEmpty && canSave }
    /// Las cuatro notas que exigen doctor_native_finish y native_complete_guard (Supabase desplegado):
    /// subjective (síntomas actuales que registra el médico), objective (exploración y observaciones),
    /// assessment (diagnóstico) y plan (plan de tratamiento). `diagnosis_code` y las medidas antiguas se reenvían intactos.
    var missingSections: [String] {
        [(subjective, "Síntomas actuales"), (objective, "Exploración y observaciones"), (assessment, "Diagnóstico"), (plan, "Plan de tratamiento")]
            .filter { $0.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.1)
    }
    var values: [String: DoctorJSON] {
        ["subjective": .string(subjective), "objective": .string(objective),
         "assessment": .string(assessment), "plan": .string(plan), "diagnosis_code": .string(diagnosis_code),
         "vitals": .object(vitals.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
            .mapValues { .string($0.replacingOccurrences(of: ",", with: ".")) })]
    }
}

/// Reglas clínicas del flujo de consulta. Espejo exacto de HospitalCore.doctorClinical (web-preview)
/// y de las validaciones desplegadas en doctor_native_save / doctor_native_finish.
enum DoctorClinicalRules {
    static let timeZone = TimeZone(identifier: "America/El_Salvador") ?? .current
    static var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = timeZone; return value }

    /// Etiqueta visible de la cita (solo texto; los estados de Supabase no cambian): programada/confirmada → Pendiente,
    /// en_atencion → En consulta, completada → Atendida, no_asistio → No atendida, cancelada → Cancelada.
    /// Idéntica a HospitalCore.doctorClinical.statusLabel.
    static func statusLabel(_ status: String) -> String {
        ["scheduled": "Pendiente", "confirmed": "Pendiente", "checked_in": "En espera", "in_progress": "En consulta",
         "completed": "Atendida", "cancelled": "Cancelada", "no_show": "No atendida", "rejected": "Rechazada"][status] ?? "Pendiente"
    }

    struct Vital: Identifiable, Sendable {
        let key: String; let label: String; let unit: String; let integer: Bool; let range: ClosedRange<Double>; let lowerExclusive: Bool
        var id: String { key }
    }
    /// Datos físicos del formulario: columnas reales de public.vital_signs con los rangos de doctor_native_save.
    static let vitals: [Vital] = [
        Vital(key: "weight_kg", label: "Peso", unit: "kg", integer: false, range: 0...1000, lowerExclusive: true),
        Vital(key: "height_cm", label: "Altura", unit: "cm", integer: false, range: 0...300, lowerExclusive: true),
        Vital(key: "temperature_c", label: "Temperatura", unit: "°C", integer: false, range: 25...50, lowerExclusive: false)]
    /// Medidas de consultas anteriores: ya no se capturan, pero se conservan al guardar y se muestran en el historial.
    struct RecordedVital: Identifiable, Sendable { let key: String; let label: String; let unit: String; var id: String { key } }
    static let recordedVitals: [RecordedVital] = vitals.map { RecordedVital(key: $0.key, label: $0.label, unit: $0.unit) } +
        [RecordedVital(key: "systolic", label: "Presión sistólica", unit: "mmHg"), RecordedVital(key: "diastolic", label: "Presión diastólica", unit: "mmHg"),
         RecordedVital(key: "heart_rate", label: "Frecuencia cardíaca", unit: "lpm")]
    /// Minutos de anticipación con que puede abrirse una consulta. `nil` = sin límite (modo de pruebas pedido el 20 de noviembre).
    /// Para restaurar la regla original usa 30 aquí y en HospitalCore.doctorClinical, y aplica supabase/doctor-start-restore-30min.sql.
    static let openingLeadMinutes: Double? = nil
    static let pendingStartMigration = "El servidor todavía solo permite abrir la consulta desde 30 minutos antes. Para pruebas a cualquier hora falta aplicar supabase/doctor-start-anytime.sql."
    /// El servidor rechazó la apertura por la regla de 30 minutos que el cliente ya no aplica.
    static func startError(_ message: String) -> String? {
        openingLeadMinutes == nil && message.localizedCaseInsensitiveContains("todavía no puede iniciarse") ? pendingStartMigration : nil
    }
    static let pendingFinishMigration = "El servidor todavía exige el plan de tratamiento para finalizar. Falta aplicar supabase/doctor-consultation-six-fields.sql; lo guardado se conserva."
    /// El cierre falló porque el servidor aún exige `plan` (migración sin aplicar) y el formulario ya no tiene ese campo.
    static func finishError(_ message: String, plan: String) -> String {
        message.localizedCaseInsensitiveContains("tratamiento") && plan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? pendingFinishMigration : message
    }

    /// Conserva solo dígitos y un separador decimal; no permite texto en campos numéricos.
    static func sanitize(_ text: String, integer: Bool) -> String {
        var result = "", separator = false
        for character in text {
            if character.isASCII && character.isNumber { result.append(character) }
            else if !integer && !separator && (character == "." || character == ",") { result.append("."); separator = true }
        }
        return String(result.prefix(integer ? 3 : 6))
    }
    static func number(_ text: String?) -> Double? {
        guard let text, !text.isEmpty else { return nil }
        return Double(text.replacingOccurrences(of: ",", with: "."))
    }
    static func vitalIssues(_ values: [String: String]) -> [String: String] {
        var issues: [String: String] = [:]
        for vital in vitals {
            guard let raw = values[vital.key], !raw.isEmpty else { continue }
            guard let value = number(raw), (!vital.integer || value == value.rounded()) else { issues[vital.key] = "Introduce un número válido."; continue }
            let low = vital.lowerExclusive ? value <= vital.range.lowerBound : value < vital.range.lowerBound
            if low || value > vital.range.upperBound {
                let lower = vital.lowerExclusive ? "mayor que \(Int(vital.range.lowerBound))" : "desde \(Int(vital.range.lowerBound))"
                issues[vital.key] = "Valor fuera de rango (\(lower) hasta \(Int(vital.range.upperBound)) \(vital.unit))."
            }
        }
        return issues
    }
    /// IMC calculado (no se guarda): solo con peso y altura válidos registrados por el médico.
    static func bmi(_ values: [String: String]) -> String? {
        guard vitalIssues(values)["weight_kg"] == nil, vitalIssues(values)["height_cm"] == nil,
              let weight = number(values["weight_kg"]), let height = number(values["height_cm"]), weight > 0, height > 0 else { return nil }
        let meters = height / 100
        return String(format: "%.1f", weight / (meters * meters))
    }
    /// Texto inicial de "Síntomas que presentaba" con lo que envió el paciente (el motivo se muestra aparte).
    /// Nunca sobrescribe una nota existente.
    static func seedSubjective(_ appointment: DoctorAppointment) -> String {
        var parts: [String] = []
        let symptoms = (appointment.symptoms ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !symptoms.isEmpty { parts.append("Síntomas referidos por el paciente: \(symptoms.joined(separator: ", "))") }
        if let other = appointment.other_symptoms?.trimmingCharacters(in: .whitespacesAndNewlines), !other.isEmpty { parts.append("Otros síntomas: \(other)") }
        return parts.joined(separator: "\n")
    }

    struct Agenda: Sendable {
        var day: [DoctorAppointment] = []
        var upcoming: [DoctorAppointment] = []
        var completed: [DoctorAppointment] = []
        var cancelled: [DoctorAppointment] = []
    }
    /// Días anteriores que se piden a doctor_native_workspace para no perder consultas en atención ni finalizadas tarde.
    static let agendaLookbackDays = 2
    static let pendingStates: Set<String> = ["scheduled", "confirmed", "checked_in", "in_progress"]

    /// Texto sin mayúsculas ni acentos para buscar por nombre, apellido, código de paciente o expediente.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_SV")).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func matches(_ appointment: DoctorAppointment, query: String) -> Bool {
        let words = fold(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return true }
        let haystack = fold([appointment.patient_name, appointment.patient_code ?? "", appointment.record_number].joined(separator: " "))
        return words.allSatisfy { haystack.contains($0) }
    }
    /// PENDIENTES: citas del día elegido que aún no se finalizan ni se cancelan, de la más temprana a la más tarde.
    /// Hoy también incluye consultas en atención abiertas en días anteriores, para poder retomarlas.
    static func pending(_ appointments: [DoctorAppointment], day: Date, now: Date = Date()) -> [DoctorAppointment] {
        let calendar = Self.calendar, today = calendar.isDate(day, inSameDayAs: now), start = calendar.startOfDay(for: day)
        return appointments.filter { appointment in
            guard pendingStates.contains(appointment.status), let date = appointment.startDate else { return false }
            if calendar.isDate(date, inSameDayAs: day) { return true }
            return today && appointment.status == "in_progress" && date < start
        }.sorted {
            let left = $0.startDate ?? .distantFuture, right = $1.startDate ?? .distantFuture
            return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
        }
    }
    /// Momento real de finalización (ended_at) o, si el servidor aún no lo publica, la hora de la cita.
    static func finishedAt(_ appointment: DoctorAppointment) -> Date? { appointment.finishedDate ?? appointment.startDate }
    /// FINALIZADAS: consultas terminadas en la fecha elegida, la última finalizada primero. Nunca canceladas ni abiertas.
    static func finished(_ appointments: [DoctorAppointment], day: Date) -> [DoctorAppointment] {
        appointments.filter { $0.status == "completed" && (finishedAt($0).map { calendar.isDate($0, inSameDayAs: day) } ?? false) }
            .sorted {
                let left = finishedAt($0) ?? .distantPast, right = finishedAt($1) ?? .distantPast
                return left == right ? $0.id.uuidString > $1.id.uuidString : left > right
            }
    }

    /// Canceladas y no atendidas de la fecha elegida: se muestran aparte en FINALIZADAS, sin mezclarse con las atendidas.
    static func closedWithoutCare(_ appointments: [DoctorAppointment], day: Date) -> [DoctorAppointment] {
        appointments.filter { ["cancelled", "no_show"].contains($0.status) && ($0.startDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false) }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    /// Orden cronológico real (fecha y hora de inicio, después id) y secciones Hoy / Próximas / Finalizadas / Canceladas.
    static func agenda(_ appointments: [DoctorAppointment], day: Date) -> Agenda {
        let calendar = Self.calendar
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let ordered = appointments.sorted {
            let left = $0.startDate ?? .distantFuture, right = $1.startDate ?? .distantFuture
            return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
        }
        var result = Agenda()
        for appointment in ordered {
            let date = appointment.startDate ?? .distantFuture
            switch appointment.status {
            case "completed": result.completed.append(appointment)
            case "cancelled", "no_show", "rejected": result.cancelled.append(appointment)
            default:
                // Días anteriores pedidos solo para retomar consultas en atención; no cuentan como citas del día.
                if date < start && appointment.status != "in_progress" { continue }
                if date < end { result.day.append(appointment) } else { result.upcoming.append(appointment) }
            }
        }
        return result
    }
}

/// Reglas del expediente: historial solo de consultas finalizadas, más reciente primero, sin campos vacíos.
enum DoctorRecordRules {
    static let historyPageSize = 10
    /// Texto real o nil; nunca se presenta un campo vacío como dato registrado.
    static func text(_ value: String?) -> String? {
        guard let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines), !clean.isEmpty else { return nil }
        return clean
    }
    /// Consultas abiertas o en borrador no forman parte del historial finalizado.
    static func finishedHistory(_ history: [DoctorConsultation]) -> [DoctorConsultation] {
        history.filter { $0.status == "closed" }.sorted {
            let left = DoctorDate.parse($0.started_at) ?? .distantPast, right = DoctorDate.parse($1.started_at) ?? .distantPast
            return left == right ? $0.id.uuidString > $1.id.uuidString : left > right
        }
    }
    static func prescriptions(_ chart: DoctorPatientChart?, encounter: UUID) -> [DoctorIssuedPrescription] {
        (chart?.prescriptions ?? []).filter { $0.encounter_id == encounter }
    }
    static func labs(_ labs: [DoctorPatientLab], encounter: UUID) -> [DoctorPatientLab] {
        labs.filter { $0.encounter_id == encounter }
    }
    /// Resultado visible solo si el laboratorio lo publicó (native_mobile_lab_page ya filtra validados y publicados).
    static func publishedResult(_ lab: DoctorPatientLab) -> Bool { lab.published_at != nil }
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
    /// Llega cuando se aplica supabase/expedientes-historial.sql.
    var encounter_id: UUID? = nil
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
