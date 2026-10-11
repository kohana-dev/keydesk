import SwiftUI
import KeydeskCore

struct RotateView: View {
    @Bindable var model: VaultModel
    let credential: Credential
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("새 키 버전 저장").font(.title2.bold())
            Text("제공사에서 발급한 새 값을 입력하세요. 아래 연결이 모두 새 버전을 사용합니다.")
            ForEach(model.snapshot?.bindings.filter { $0.credentialID == credential.id } ?? []) { binding in
                Text("\(model.snapshot?.projects.first { $0.id == binding.projectID }?.name ?? "") · \(binding.environment.title) · \(binding.variable)").font(.caption)
            }
            SecretInput(title: "새 키 값", value: $value)
            Text("기존 버전은 이력에 남습니다. 실행 중인 앱·배포의 반영과 제공사의 구 키 폐기는 별도입니다.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red) }
            HStack { Button("취소") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("새 버전 저장") { do { try model.rotate(credential.id, value: value); dismiss() } catch { self.error = error.localizedDescription } }.buttonStyle(.borderedProminent).disabled(value.isEmpty) }
        }.padding(28).frame(width: 560)
        .onDisappear { value = "" }
    }
}
