import AppKit

/// A small template rendition of Cellar's ribbon wine opener.
/// macOS supplies the foreground color for light/dark menu bars.
@MainActor
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 20), flipped: false) { _ in
            NSColor.black.setStroke()
            let handle = NSBezierPath()
            handle.lineWidth = 2.1; handle.lineCapStyle = .round; handle.lineJoinStyle = .round
            handle.move(to: NSPoint(x: 2.5, y: 16))
            handle.curve(to: NSPoint(x: 15.5, y: 16), controlPoint1: NSPoint(x: 6, y: 17.2), controlPoint2: NSPoint(x: 12, y: 17.2))
            handle.stroke()
            let ribbon = NSBezierPath()
            ribbon.lineWidth = 1.8; ribbon.lineCapStyle = .round; ribbon.lineJoinStyle = .round
            ribbon.move(to: NSPoint(x: 9, y: 16))
            ribbon.line(to: NSPoint(x: 9, y: 12.8))
            ribbon.curve(to: NSPoint(x: 7, y: 9.2), controlPoint1: NSPoint(x: 15, y: 12), controlPoint2: NSPoint(x: 12, y: 10))
            ribbon.curve(to: NSPoint(x: 11, y: 6.6), controlPoint1: NSPoint(x: 2, y: 8.4), controlPoint2: NSPoint(x: 6, y: 7.4))
            ribbon.curve(to: NSPoint(x: 7.5, y: 3.7), controlPoint1: NSPoint(x: 15, y: 5.8), controlPoint2: NSPoint(x: 10, y: 4.6))
            ribbon.line(to: NSPoint(x: 9, y: 2))
            ribbon.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Cellar"
        return image
    }()
}
