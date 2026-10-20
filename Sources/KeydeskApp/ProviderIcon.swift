import SwiftUI
import AppKit
import KeydeskCore

// Brand artwork is bundled locally. Weather services share a system symbol; unknown services use initials.
struct ProviderLogo: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
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
    private static func symbol(for provider: String) -> String? {
        ProviderName.weatherProviders.contains(ProviderName.canonical(provider)) ? "cloud.sun.fill" : nil
    }
    static func menuImage(for provider: String) -> Image? {
        if let symbol = symbol(for: provider) { return Image(systemName: symbol) }
        guard let original = images[provider.lowercased()], let copy = original.copy() as? NSImage else { return nil }
        copy.size = NSSize(width: 16, height: 16)
        return Image(nsImage: copy)
    }
    var body: some View {
        let _ = interfaceLanguage
        let name = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        Group {
            if let image = Self.images[name.lowercased()] {
                Image(nsImage: image).resizable().scaledToFit()
            } else if let symbol = Self.symbol(for: name) {
                Image(systemName: symbol).resizable().scaledToFit().symbolRenderingMode(.multicolor)
            } else {
                Text(name == "Other" ? L10n.tr("기타", "Other") : String(name.prefix(2)).uppercased())
                    .font(.system(size: size * 0.48, weight: .semibold)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.6)
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
