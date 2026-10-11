import SwiftUI
import KeydeskCore

struct SecretFileReplacement: View {
    @Bindable var model: VaultModel
    let credential: Credential
    @State private var file: SecretFile?
    var body: some View {
        DisclosureGroup("파일 교체") {
            SecretFileInput(file: $file)
            Button("새 파일 버전 저장") {
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
        try mutate { next in
            guard let index = next.credentials.firstIndex(where: { $0.id == id }) else { throw VaultError.invalidData }
            if let file = version.file { next.credentials[index].rotate(to: try file.validated()) }
            else { next.credentials[index].rotate(to: version.value) }
            next.record("키 또는 파일 새 버전 저장")
        }
    }
}
