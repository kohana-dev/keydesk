import SwiftUI
import AppKit

/// Reuse the installed icon rather than introducing a second brand symbol.
struct CellarMark: View {
    var size: CGFloat = 48
    private static let icon: NSImage? = Bundle.main.resourceURL
        .flatMap { NSImage(contentsOf: $0.appendingPathComponent("Cellar.icns")) }
    var body: some View {
        Group {
            if let icon = Self.icon { Image(nsImage: icon).resizable().scaledToFit() }
            else { Text("C").font(.system(size: size * 0.6, weight: .semibold)).foregroundStyle(Theme.accent) }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
