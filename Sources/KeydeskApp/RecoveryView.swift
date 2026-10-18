import SwiftUI
import KeydeskCore

struct RecoveryView: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Bindable var model: VaultModel
    var initialURL: URL? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var url: URL?
    @State private var code = ""
    @State private var result: String?
    @State private var busy = false
    var body: some View {
        let _ = interfaceLanguage
        VStack(spacing: 0) {
            DialogCloseBar { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(model.exists ? L10n.tr("백업 복구 검증", "Verify backup recovery") : L10n.tr("암호화 백업 복원", "Restore encrypted backup")).font(.title2.bold())
                    Text(L10n.tr("백업과 복구 키를 함께 확인합니다. 기존 금고는 덮어쓰지 않습니다.", "Check the backup and recovery key together. Your existing vault will not be overwritten.")).foregroundStyle(.secondary)
                    Button(url?.lastPathComponent ?? L10n.tr("백업 파일 선택", "Choose backup file"), systemImage: "doc.badge.arrow.up") {
                        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
                        if panel.runModal() == .OK { url = panel.url; result = nil }
                    }
                    SecretInput(title: L10n.tr("복구 키", "Recovery key"), value: $code)
                    if let result { Text(result).font(.callout).textSelection(.enabled) }
                    if model.exists && !model.isDemo {
                        Button(L10n.tr("이 Mac의 금고 접근 복구", "Recover vault access on this Mac"), systemImage: "key") {
                            guard let url else { return }; busy = true
                            Task {
                                defer { busy = false }
                                do { try await model.recoverDeviceAccess(at: url, code: code); dismiss() }
                                catch { result = error.localizedDescription }
                            }
                        }.disabled(url == nil || code.isEmpty || busy)
                        Text(L10n.tr("기기 Keychain이 유실된 경우 같은 금고의 백업과 복구 키로 접근만 복구합니다. 과거 백업으로 현재 데이터를 덮어쓰지 않습니다.", "If this device’s Keychain is lost, use a backup of the same vault and its recovery key to recover access only. Current data will not be overwritten with an older backup.")).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(28)
            }
            DialogFooter {
                DialogDismissButton(prominent: false) { dismiss() }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button(model.exists ? L10n.tr("복구 가능 여부 검증", "Verify recoverability") : L10n.tr("이 기기에 복원", "Restore on this Mac")) {
                    guard let url else { return }; busy = true
                    Task {
                        defer { busy = false }
                        do {
                            if model.exists { let count = try model.validateRecovery(at: url, code: code); result = L10n.tr("복구 검증 성공 · 보관된 키 \(count)개. 기존 금고는 변경하지 않았습니다.", "Recovery verified · \(count) stored keys. Your existing vault was not changed.") }
                            else { try await model.restore(at: url, code: code); dismiss() }
                        } catch { result = error.localizedDescription }
                    }
                }.buttonStyle(.borderedProminent).disabled(url == nil || code.isEmpty || busy)
            }
        }.frame(width: 560, height: DialogSizing.height(preferred: 522))
        .onAppear { if url == nil { url = initialURL } }
        .onDisappear { code = "" }
    }
}
