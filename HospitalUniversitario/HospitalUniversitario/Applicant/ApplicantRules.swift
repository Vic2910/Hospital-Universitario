import Foundation
import JavaScriptCore

/// Reglas del solicitante sin expediente. Usa `Shared/hospital-core.js`, el mismo archivo
/// que la vista previa web, para que validación, formato y estados coincidan.
/// Solo valida y formatea: no consulta ni escribe en Supabase.
@MainActor
final class ApplicantRules {
    static let shared = ApplicantRules()

    private let context: JSContext?

    private init() {
        let context = JSContext()
        if let url = Bundle.main.url(forResource: "hospital-core", withExtension: "js"),
           let script = try? String(contentsOf: url, encoding: .utf8) {
            context?.evaluateScript(script)
        }
        self.context = context
    }

    static func isoDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func call(_ name: String, _ arguments: [Any]) -> JSValue? {
        context?.objectForKeyedSubscript("HospitalCore")?.objectForKeyedSubscript(name)?.call(withArguments: arguments)
    }

    private func message(_ value: JSValue?) -> String? {
        guard let value, !value.isUndefined else {
            return "No se pudieron cargar las reglas de validación. Vuelve a abrir la aplicación."
        }
        if value.isNull { return nil }
        return value.objectForKeyedSubscript("message")?.toString()
    }

    var specialties: [String] {
        context?.objectForKeyedSubscript("HospitalCore")?.objectForKeyedSubscript("applicantDemoSpecialties")?.toArray() as? [String] ?? []
    }

    func periodLabel(_ key: String) -> String {
        context?.objectForKeyedSubscript("HospitalCore")?.objectForKeyedSubscript("applicantPeriods")?.objectForKeyedSubscript(key)?.toString() ?? key
    }

    func formatDUI(_ value: String) -> String {
        call("formatDui", [value])?.toString() ?? value
    }

    func formatPhone(_ value: String) -> String {
        call("formatPhone", [value])?.toString() ?? value
    }

    var cities: [String] {
        context?.objectForKeyedSubscript("HospitalCore")?.objectForKeyedSubscript("registrationCities")?.toArray() as? [String] ?? []
    }

    private func personalDictionary(_ data: ApplicantPersonalData) -> [String: Any] {
        let birth: Any = data.birthDate.map { Self.isoDay($0) as Any } ?? NSNull()
        return ["given": data.given, "family": data.family, "dui": data.dui, "phone": data.phone, "birthDate": birth]
    }

    /// Primer problema de los datos personales, o nil si son válidos.
    func validatePersonal(_ data: ApplicantPersonalData, today: Date = Date()) -> String? {
        message(call("validatePersonalData", [personalDictionary(data), Self.isoDay(today)]))
    }

    /// Datos personales más correo y contraseña, para el registro.
    func validateAccount(_ data: ApplicantPersonalData, email: String, password: String, confirm: String, today: Date = Date()) -> String? {
        var input = personalDictionary(data)
        input["email"] = email
        input["password"] = password
        input["confirm"] = confirm
        return message(call("validateApplicantProfile", [input, Self.isoDay(today)]))
    }

    func validateRequest(_ draft: ApplicantRequestDraft, today: Date = Date()) -> String? {
        let input: [String: Any] = [
            "specialty": draft.specialty,
            "reason": draft.reason,
            "date": Self.isoDay(draft.date),
            "period": draft.period
        ]
        return message(call("validateAttentionRequest", [input, Self.isoDay(today)]))
    }

    /// Estado de interfaz a partir del estado de la solicitud y, si existe, de la cita asociada.
    func stateView(status: String, appointmentStatus: String?) -> (key: String, label: String) {
        let appointment: Any = appointmentStatus.map { $0 as Any } ?? NSNull()
        guard let value = call("applicantStateView", [status, appointment]),
              let key = value.objectForKeyedSubscript("key")?.toString(),
              let label = value.objectForKeyedSubscript("label")?.toString() else {
            return ("unknown", "Estado no disponible")
        }
        return (key, label)
    }
}
