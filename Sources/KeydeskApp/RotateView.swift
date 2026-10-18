import SwiftUI
import KeydeskCore

struct RotateView: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Bindable var model: VaultModel
    let credential: Credential
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var error: String?
    var body: some View {
        let _ = interfaceLanguage
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(L10n.tr("새 키 버전 저장", "New key version")).font(.title2.bold())
                    Text(L10n.tr("제공사에서 발급한 새 값을 입력하세요. 아래 연결이 모두 새 버전을 사용합니다.", "Enter the new value issued by the provider. Every connection below will use the new version."))
                    ForEach(model.snapshot?.bindings.filter { $0.credentialID == credential.id } ?? []) { binding in
                        Text("\(model.snapshot?.projects.first { $0.id == binding.projectID }?.name ?? "") · \(binding.environment.title) · \(binding.variable)").font(.caption)
                    }
                    SecretInput(title: L10n.tr("새 키 값", "New key value"), value: $value)
                    Text(L10n.tr("기존 버전은 이력에 남습니다. 실행 중인 앱·배포의 반영과 제공사의 구 키 폐기는 별도입니다.", "Previous versions remain in history. Updating running apps or deployments and revoking the old key with the provider are separate steps.")).font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red) }
                }.padding(28)
            }
            DialogFooter { DialogDismissButton(L10n.tr("취소", "Cancel"), prominent: false) { dismiss() }; Spacer(); Button(L10n.tr("새 버전 저장", "Save new version")) { do { try model.rotate(credential.id, value: value); dismiss() } catch { self.error = error.localizedDescription } }.buttonStyle(.borderedProminent).disabled(value.isEmpty) }
        }.frame(width: 560, height: DialogSizing.height(preferred: 492))
        .onDisappear { value = "" }
    }
}
