import SwiftUI

extension Color {
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let scanner = Scanner(string: sanitized)
        var value: UInt64 = 0

        guard scanner.scanHexInt64(&value), sanitized.count == 6 else {
            self = .accentColor
            return
        }

        let red = Double((value & 0xFF0000) >> 16) / 255
        let green = Double((value & 0x00FF00) >> 8) / 255
        let blue = Double(value & 0x0000FF) / 255

        self = Color(red: red, green: green, blue: blue)
    }
}

extension LibraryLabelColor {
    var swiftUIColor: Color {
        Color(hex: hexColor)
    }
}
