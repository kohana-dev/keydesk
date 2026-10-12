import SwiftUI
import KeydeskCore

struct ProjectAvatar: View {
    let project: Project
    var size: CGFloat = 26
    var body: some View {
        Group {
            if let data = project.iconPNG, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Text(String(project.name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.48, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.projectColors[abs(project.colorIndex % Theme.projectColors.count)])
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.surface)
            }
        }.frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24))
            .overlay(RoundedRectangle(cornerRadius: size * 0.24).strokeBorder(Theme.border.opacity(0.6), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}
