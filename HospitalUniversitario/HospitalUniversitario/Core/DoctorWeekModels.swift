import Foundation
import UserNotifications

/// Semana laboral del médico calculada por HospitalCore.doctorWeek (Shared/hospital-core.js) con los datos reales que
/// asigna administración: doctor_schedules, staff_shifts, staff_absences y la jornada recurrente (doctor_native_schedule,
/// staff_recurring_journeys.breaks). Almuerzo y descanso solo si están registrados; los huecos son «Entre jornadas».
struct DoctorWeek: Decodable, Equatable {
    /// kind: "lunch" (almuerzo registrado), "break" (descanso registrado) o "gap" (tiempo entre jornadas sin registro).
    struct Block: Decodable, Equatable { let start: String; let end: String; var shift: String? = nil; var kind: String? = nil; var label: String? = nil }
    struct Shift: Decodable, Equatable { let start: String; let end: String; let type: String; let status: String }
    struct Absence: Decodable, Equatable { let reason: String; let all_day: Bool; let start: String?; let end: String? }
    struct Day: Decodable, Equatable, Identifiable {
        let date: String
        let weekday: String
        let today: Bool
        let blocks: [Block]
        let breaks: [Block]
        let shifts: [Shift]
        let absences: [Absence]
        let minutes: Int
        let free: Bool
        var id: String { date }
    }
    let week_start: String
    let week_end: String
    let total_minutes: Int
    let days: [Day]

    static func hours(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }
}

/// Recordatorios locales (10 minutos antes) solo de almuerzos y descansos REGISTRADOS por administración; nunca de los huecos
/// «Entre jornadas». Solo si el médico ya autorizó notificaciones; identificadores estables y se retiran los que no corresponden.
enum DoctorBreakReminders {
    static let prefix = "hospital.break."
    static func schedule(_ week: DoctorWeek) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let parser = DateFormatter(); parser.locale = Locale(identifier: "en_US_POSIX"); parser.timeZone = DoctorClinicalRules.timeZone
        parser.dateFormat = "yyyy-MM-dd HH:mm"
        var wanted: [String: (Date, String, Bool)] = [:]
        for day in week.days {
            for item in day.breaks where item.kind == "lunch" || item.kind == "break" {
                guard let start = parser.date(from: "\(day.date) \(item.start)") else { continue }
                wanted[prefix + day.date + "." + item.start] = (start, item.end, item.kind == "lunch")
            }
        }
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) && wanted[$0] == nil })
        let existing = Set(pending.map(\.identifier))
        for (identifier, value) in wanted where !existing.contains(identifier) {
            let delay = value.0.addingTimeInterval(-10 * 60).timeIntervalSinceNow
            guard delay > 1 else { continue }
            let content = UNMutableNotificationContent()
            content.title = value.2 ? "Tu almuerzo comienza en 10 minutos" : "Tu descanso comienza en 10 minutos"
            content.body = "Según tu jornada, termina a las \(value.1)."
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)))
        }
    }
}
