import SwiftUI
import CryptoKit
import KeydeskCore

struct VaultKeyRotationView: View {
    @Bindable var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var dataKey = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("금고 키 교체").font(.title2.bold())
            Text("새 복구 키를 만들어 iCloud 키체인과 백업에 반영합니다. 이전 백업 파일은 이전 복구 키로 계속 열 수 있습니다. 복구 키가 유출됐다고 의심되면 데이터 암호화 키도 함께 교체하세요.").foregroundStyle(.secondary)
            Toggle("데이터 암호화 키도 교체", isOn: $dataKey)
            if model.backupDirectory == nil { Text("먼저 백업 폴더를 정하세요.").font(.caption).foregroundStyle(.red) }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if busy { ProgressView() }
                Button("새 백업 검증 후 교체") {
                    busy = true
                    Task {
                        defer { busy = false }
                        do { try await model.rotateVaultKeys(code: RecoveryCode.encode(SymmetricKey(size: .bits256)), dataKey: dataKey); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }.buttonStyle(.borderedProminent).disabled(busy || model.backupDirectory == nil)
            }
        }.padding(28).frame(width: 600).interactiveDismissDisabled(busy)
    }
}
