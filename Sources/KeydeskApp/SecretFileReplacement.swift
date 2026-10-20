import SwiftUI
import KeydeskCore

struct SecretFileReplacement: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Bindable var model: VaultModel
    let credential: Credential
    @State private var file: SecretFile?
    var body: some View {
        let _ = interfaceLanguage
        DisclosureGroup(L10n.tr("파일 교체", "Replace file")) {
            SecretFileInput(file: $file)
            Button(L10n.tr("새 파일 버전 저장", "Save new version")) {
                guard let file else { return }
                do {
                    try model.restoreVersion(credential.id, version: SecretVersion(file: file)); self.file = nil
                } catch { model.error = error.localizedDescription }
            }.disabled(file == nil)
        }
    }
}
extension VaultModel {
    func restoreVersion(_ id: UUID, version: SecretVersion) throws {
        _ = try version.validated()
        try mutate { next in
            guard let index = next.credentials.firstIndex(where: { $0.id == id }) else { throw VaultError.invalidData }
            if let file = version.file { next.credentials[index].rotate(to: try file.validated()) }
            else { next.credentials[index].rotate(to: version.value, format: version.format) }
            next.record("항목 버전 복원")
        }
        hideValue()
    }
}
