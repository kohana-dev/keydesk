import SwiftUI
import KeydeskCore

struct CLIApprovalView: View {
    @Bindable var model: VaultModel
    let approval: CLIApproval
    @State private var busy = false
    @State private var remember = false
    init(model: VaultModel, approval: CLIApproval) {
        self.model = model; self.approval = approval
        _remember = State(initialValue: approval.request.environment != .production)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("CLI 실행 요청", systemImage: "terminal").font(.title2.bold())
            Text("프로젝트: \(approval.request.project)")
            Text("환경: \(approval.request.environment.title)").foregroundStyle(approval.request.environment == .production ? .orange : .primary)
            Text("작업 폴더: \(approval.request.directory)").font(.caption).textSelection(.enabled)
            Text("실행 파일: \(approval.executable.path)").font(.caption).textSelection(.enabled)
            ScrollView { Text(approval.request.command.joined(separator: "\n")).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 160).padding(14).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 10))
            let warnings = CommandRisk.warnings(for: approval.request.command)
            if !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("키가 노출될 수 있는 명령입니다", systemImage: "exclamationmark.triangle.fill").font(.headline)
                    ForEach(warnings, id: \.self) { Text("• " + $0).font(.callout) }
                    Text("AI가 만든 명령이라면 내용을 확인한 뒤 허용하세요.").font(.callout)
                }.foregroundStyle(.orange).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
            if let key = approval.request.stdinKey { Text("표준입력에만 전달: \(key)").font(.caption) }
            if let files = approval.request.fileVariables { Text("임시 파일 경로로 전달: \(files.joined(separator: ", "))").font(.caption) }
            if let variables = approval.request.variables { Text("선택 변수: \(variables.joined(separator: ", "))").font(.caption) }
            Text("명시한 키만 전달합니다. 실행 코드는 키를 읽거나 외부로 전송할 수 있습니다. 요청의 프로젝트·경로·명령은 호출자가 제공한 정보입니다. 승인 후 실행 파일이 바뀌면 거부합니다. 스크립트와 하위 프로그램까지 검증하지는 않습니다.").font(.callout).foregroundStyle(.secondary)
            Text(approval.request.interactive == true ? "대화형 터미널 · TTY 사용" : "표준입력과 출력 전달").font(.caption)
            Text(approval.request.keepRunning == true ? "금고 잠금 후에도 이 실행을 유지합니다. 이미 전달된 키도 프로세스에 남습니다. CLI 연결이나 앱 종료 시 종료를 요청합니다." : "금고 잠금 시 종료를 요청합니다.").font(.caption).foregroundStyle(.secondary)
            if DevelopmentApprovalCache.eligible(approval.request) {
                Toggle(approval.request.environment == .production ? "동일한 운영 명령을 5분간 최대 10회 재실행 허용" : "동일한 개발 명령을 30분간 허용", isOn: $remember)
                if approval.request.environment == .production {
                    Text("최초 허용 시 OS 인증이 필요합니다. 기간은 재실행으로 연장되지 않습니다. 직접 지정한 파일과 일부 패키지 설정도 확인하지만, 불러오는 의존성과 하위 프로그램은 검증하지 않습니다. 재사용은 매번 승인하는 것보다 확인 기회를 줄입니다.").font(.caption).foregroundStyle(.orange)
                }
                Text("프로젝트·키 이름·폴더·명령·실행 파일이 같을 때 재사용합니다. 잠금·키 변경·앱 종료 시 해제됩니다. 이 도구가 불러오는 코드와 하위 프로그램은 바뀔 수 있습니다.").font(.caption).foregroundStyle(.secondary)
            }
            HStack { Button("거절") { model.rejectCLI() }.keyboardShortcut(.cancelAction); Spacer(); if busy { ProgressView().controlSize(.small) }; Button("이번 실행 허용") { busy = true; Task { await model.acceptCLI(remember: remember); busy = false } }.buttonStyle(.borderedProminent).disabled(busy) }
        }.padding(28).frame(width: 650)
        .interactiveDismissDisabled(busy)
    }
}
