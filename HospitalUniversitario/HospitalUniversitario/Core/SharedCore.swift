import Foundation
import JavaScriptCore

enum HospitalError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

struct BackendConfiguration: Decodable {
    let url: URL
    let publishableKey: String

    static func load(bundle: Bundle = .main) throws -> BackendConfiguration {
        guard let value = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil,
              !value.contains("$("),
              let key = bundle.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String,
              !key.isEmpty, !key.contains("$("), !key.hasPrefix("sb_secret_") else {
            throw HospitalError.message("Configura Supabase.local.xcconfig con la URL y la clave pública del hospital.")
        }
        return BackendConfiguration(url: url, publishableKey: key)
    }
}

/// Uses exactly the same JavaScript policy and request builder as the web preview.
@MainActor
final class SharedCore {
    private let context: JSContext
    let configuration: BackendConfiguration

    init() throws {
        guard let context = JSContext(),
              let script = Bundle.main.url(forResource: "hospital-core", withExtension: "js"),
              Bundle.main.url(forResource: "contract", withExtension: "json") != nil else {
            throw HospitalError.message("No se encontraron los recursos compartidos del target.")
        }
        self.context = context
        configuration = try BackendConfiguration.load()
        context.evaluateScript(try String(contentsOf: script, encoding: .utf8))
        if context.exception != nil { throw HospitalError.message("No se pudo cargar el contrato compartido.") }
    }

    func call(_ name: String, arguments: [Any]) throws -> JSValue {
        context.exception = nil
        guard let result = context.objectForKeyedSubscript("HospitalCore")?.objectForKeyedSubscript(name)?.call(withArguments: arguments),
              context.exception == nil, !result.isUndefined else {
            throw HospitalError.message("No se pudo interpretar la respuesta del hospital.")
        }
        return result
    }

    func roles(_ access: Data) throws -> [String] {
        let object = try JSONSerialization.jsonObject(with: access)
        return try call("routes", arguments: [object]).toArray() as? [String] ?? []
    }

    func turnResource(_ role: String) throws -> String {
        try call("turnResource", arguments: [role]).toString()
    }

    func weekWindow() throws -> String { try call("weekWindow", arguments: []).toString() }

    func request(resource: String, cursor: [String: Any]?, owner: UUID? = nil, window: String? = nil) throws -> Data {
        let object = try call("readRequest", arguments: [resource, cursor as Any? ?? NSNull(), owner?.uuidString as Any? ?? NSNull(), window as Any? ?? NSNull()]).toDictionary()!
        return try JSONSerialization.data(withJSONObject: object)
    }

    func interval(_ value: String) -> DateInterval? {
        guard let bounds = try? call("periodBounds", arguments: [value]).toDictionary(),
              let start = bounds["start"] as? String, let end = bounds["end"] as? String else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let first = parser.date(from: start), let last = parser.date(from: end) else { return nil }
        return DateInterval(start: first, end: last)
    }

    func period(_ value: String) -> String {
        guard let interval = interval(value) else { return "Horario no disponible" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_SV")
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(formatter.string(from: interval.start)) – \(formatter.string(from: interval.end))"
    }
}
