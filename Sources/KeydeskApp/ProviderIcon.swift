import SwiftUI
import AppKit
import KeydeskCore

// Brand artwork is bundled locally. Unknown services use their own initials.
struct ProviderLogo: View {
    let provider: String
    var size: CGFloat = 24
    private struct Asset: Decodable { let provider: String; let file: String }
    private static let images: [String: NSImage] = {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("ProviderLogos/manifest.json"),
              let data = try? Data(contentsOf: url),
              let assets = try? JSONDecoder().decode([Asset].self, from: data) else { return [:] }
        return assets.reduce(into: [:]) { result, asset in
            let path = url.deletingLastPathComponent().appendingPathComponent(asset.file + ".png")
            if let image = NSImage(contentsOf: path) { result[asset.provider.lowercased()] = image }
        }
    }()
    static func menuImage(for provider: String) -> Image? {
        guard let original = images[provider.lowercased()], let copy = original.copy() as? NSImage else { return nil }
        copy.size = NSSize(width: 16, height: 16)
        return Image(nsImage: copy)
    }
    var body: some View {
        let name = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        Group {
            if let image = Self.images[name.lowercased()] {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Text(name == "Other" ? "기타" : String(name.prefix(2)).uppercased())
                    .font(.system(size: size * 0.48, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct ProviderIcon: View {
    let provider: String
    var body: some View {
        ProviderLogo(provider: provider)
            .frame(width: 42, height: 42)
            .background(.white, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(.black.opacity(0.06)))
    }
}
