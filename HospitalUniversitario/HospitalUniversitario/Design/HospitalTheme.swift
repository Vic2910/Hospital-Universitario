import SwiftUI

enum HospitalTheme {
    static let wine = Color(red: 119/255, green: 7/255, blue: 39/255)
    static let background = Color(red: 248/255, green: 248/255, blue: 250/255)
    static let ink = Color(red: 36/255, green: 41/255, blue: 54/255)
    static let secondary = Color(red: 117/255, green: 126/255, blue: 145/255)
    static let rose = Color(red: 251/255, green: 234/255, blue: 240/255)
    static let green = Color(red: 227/255, green: 246/255, blue: 234/255)
}

struct HospitalCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct HospitalBadge: View {
    let text: String
    var warning = false
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 5).frame(minWidth: 100, alignment: .leading)
            .background(warning ? Color(red: 1, green: 0.95, blue: 0.85) : HospitalTheme.green, in: Capsule())
    }
}

enum HospitalLabels {
    static func status(_ value: String) -> String {
        ["pending":"Pendiente", "confirmed":"Confirmado", "cancelled":"Cancelado", "waiting":"En espera", "called":"Llamado", "in_service":"En atención", "completed":"Finalizado"][value] ?? value
    }
}
