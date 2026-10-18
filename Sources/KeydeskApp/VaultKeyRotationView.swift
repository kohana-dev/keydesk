import SwiftUI
import CryptoKit
import KeydeskCore

struct VaultKeyRotationView: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Bindable var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var dataKey = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        let _ = interfaceLanguage
        VStack(spacing: 0) {
            DialogCloseBar { dismiss() }.disabled(busy)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(L10n.tr("금고 키 교체", "Rotate vault keys")).font(.title2.bold())
                    Text(L10n.tr("새 복구 키를 만들어 iCloud 키체인과 백업에 반영합니다. 이전 백업 파일은 이전 복구 키로 계속 열 수 있습니다. 복구 키가 유출됐다고 의심되면 데이터 암호화 키도 함께 교체하세요.", "Create a new recovery key and update iCloud Keychain and the backup. Previous backup files can still be opened with the previous recovery key. If you suspect the recovery key was exposed, rotate the data encryption key as well.")).foregroundStyle(.secondary)
                    Toggle(L10n.tr("데이터 암호화 키도 교체", "Also rotate the data encryption key"), isOn: $dataKey)
                    if model.backupDirectory == nil { Text(L10n.tr("먼저 백업 폴더를 정하세요.", "Choose a backup folder first.")).font(.caption).foregroundStyle(.red) }
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                }.padding(28)
            }
            DialogFooter {
                DialogDismissButton(L10n.tr("취소", "Cancel"), prominent: false) { dismiss() }
                Spacer()
                if busy { ProgressView() }
                Button(L10n.tr("새 백업 검증 후 교체", "Verify new backup and rotate")) {
                    busy = true
                    Task {
                        defer { busy = false }
                        do { try await model.rotateVaultKeys(code: RecoveryCode.encode(SymmetricKey(size: .bits256)), dataKey: dataKey); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }.buttonStyle(.borderedProminent).disabled(busy || model.backupDirectory == nil)
            }
        }.frame(width: 600, height: DialogSizing.height(preferred: 440)).interactiveDismissDisabled(busy)
    }
}
