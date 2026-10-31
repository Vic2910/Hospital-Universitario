import SwiftUI

/// Paleta vino y rojo del proyecto, derivada de las imágenes de referencia.
/// Se define como extensión de `Color` para reutilizarla en toda la app.
extension Color {
    /// Tono principal de marca: encabezados y acciones primarias.
    static let vinoPrincipal = Color(red: 119/255, green: 7/255, blue: 39/255)
    /// Acento rojo para iconos, bordes y detalles destacados.
    static let rojoAcento = Color(red: 164/255, green: 19/255, blue: 60/255)
    /// Fondo de tarjetas.
    static let fondoCard = Color.white
    /// Fondo general de la app (gris neutro claro, permitido para legibilidad).
    static let fondoApp = Color(red: 248/255, green: 248/255, blue: 250/255)
}

/// Degradado del vino para las tarjetas destacadas.
extension LinearGradient {
    static let vinoDestacado = LinearGradient(
        colors: [.vinoPrincipal, Color(red: 77/255, green: 4/255, blue: 26/255)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
