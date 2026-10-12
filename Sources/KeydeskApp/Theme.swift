import SwiftUI

/// Cellar's blue ribbon identity on quiet, cool neutral surfaces.
enum Theme {
    static let accent = Color(red: 0.16, green: 0.31, blue: 0.88)
    static let violet = Color(red: 0.40, green: 0.28, blue: 0.77)
    static let canvas = Color(red: 0.973, green: 0.974, blue: 0.980)
    static let sidebar = Color(red: 0.950, green: 0.951, blue: 0.965)
    static let surface = Color.white
    static let selection = Color(red: 0.892, green: 0.922, blue: 0.992)
    static let border = Color(red: 0.87, green: 0.88, blue: 0.91)
    static let ink = Color(red: 0.10, green: 0.13, blue: 0.22)
    static let projectColors: [Color] = [accent, violet, Color(red: 0.38, green: 0.44, blue: 0.56)]
}

extension View {
    func cellarCard() -> some View {
        clipShape(RoundedRectangle(cornerRadius: 14))
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border.opacity(0.8), lineWidth: 0.7))
    }
}
