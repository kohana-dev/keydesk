import SwiftUI
import KeydeskCore

struct DepositView: View {
    let model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var project = ""
    @State private var variable = ""
    @State private var value = ""
    @State private var environment = EnvironmentName.development
    @State private var result: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("잠금 중 새 키 맡기기").font(.title2.bold())
            Text("새 키만 암호화 접수합니다. 기존 키는 읽거나 변경할 수 없습니다. 잠금을 해제할 때 금고에 편입되고 iCloud 백업됩니다.").foregroundStyle(.secondary)
            TextField("프로젝트 이름", text: $project)
            Picker("환경", selection: $environment) { ForEach(EnvironmentName.allCases, id: \.self) { Text($0.title).tag($0) } }
            TextField("환경변수 이름 (예: API_KEY)", text: $variable)
            SecretInput(title: "새 키 값", value: $value)
            if let result { Text(result).font(.callout) }
            HStack {
                Button("닫기") { dismiss() }
                Spacer()
                Button("암호화 접수") {
                    do { result = try model.deposit(SecretDeposit(project: project, environment: environment, variable: variable, value: value)); value = "" }
                    catch { result = "접수하지 못했습니다. 금고를 한 번 열어 접수 키를 준비하거나 입력을 확인하세요." }
                }.buttonStyle(.borderedProminent).disabled(project.isEmpty || variable.isEmpty || value.isEmpty)
            }
        }.padding(28).frame(width: 560).textFieldStyle(.roundedBorder)
        .onDisappear { value = "" }
    }
}
