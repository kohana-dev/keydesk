import SwiftUI
import KeydeskCore

struct RecoveryView: View {
    @Bindable var model: VaultModel
    var initialURL: URL? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var url: URL?
    @State private var code = ""
    @State private var result: String?
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.exists ? "백업 복구 검증" : "암호화 백업 복원").font(.title2.bold())
            Text("백업과 복구 키를 함께 확인합니다. 기존 금고는 덮어쓰지 않습니다.").foregroundStyle(.secondary)
            Button(url?.lastPathComponent ?? "백업 파일 선택", systemImage: "doc.badge.arrow.up") {
                let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
                if panel.runModal() == .OK { url = panel.url; result = nil }
            }
            SecretInput(title: "복구 키", value: $code)
            if let result { Text(result).font(.callout).textSelection(.enabled) }
            if model.exists && !model.isDemo {
                Button("이 Mac의 금고 접근 복구", systemImage: "key") {
                    guard let url else { return }; busy = true
                    Task {
                        defer { busy = false }
                        do { try await model.recoverDeviceAccess(at: url, code: code); dismiss() }
                        catch { result = error.localizedDescription }
                    }
                }.disabled(url == nil || code.isEmpty || busy)
                Text("기기 Keychain이 유실된 경우 같은 금고의 백업과 복구 키로 접근만 복구합니다. 과거 백업으로 현재 데이터를 덮어쓰지 않습니다.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button(model.exists ? "복구 가능 여부 검증" : "이 기기에 복원") {
                    guard let url else { return }; busy = true
                    Task {
                        defer { busy = false }
                        do {
                            if model.exists { let count = try model.validateRecovery(at: url, code: code); result = "복구 검증 성공 · 보관된 키 \(count)개. 기존 금고는 변경하지 않았습니다." }
                            else { try await model.restore(at: url, code: code); dismiss() }
                        } catch { result = error.localizedDescription }
                    }
                }.buttonStyle(.borderedProminent).disabled(url == nil || code.isEmpty || busy)
            }
        }.padding(28).frame(width: 560)
        .onAppear { if url == nil { url = initialURL } }
        .onDisappear { code = "" }
    }
}
