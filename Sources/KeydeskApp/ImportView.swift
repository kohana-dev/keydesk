import SwiftUI
import KeydeskCore

struct ImportView: View {
    @Bindable var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [DotenvRow] = []
    @State private var replace = false
    @State private var filename: String?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(".env 가져오기 미리보기").font(.title2.bold())
            Text("선택한 파일만 읽습니다. 값은 표시하지 않고 입력 구문은 실행하지 않습니다.").foregroundStyle(.secondary)
            Button(filename ?? ".env 파일 선택", systemImage: "doc") {
                let panel = NSOpenPanel(); panel.showsHiddenFiles = true; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
                guard panel.runModal() == .OK, let url = panel.url else { return }
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    guard let size = attributes[.size] as? NSNumber, size.intValue <= 1_048_576 else { throw VaultError.invalidData }
                    rows = DotenvParser.parse(try String(contentsOf: url, encoding: .utf8)); filename = url.lastPathComponent; error = nil
                } catch { self.error = "파일을 읽지 못했습니다. UTF-8, 1MB 이하 파일을 선택하세요." }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { row in
                        let conflict = model.snapshot?.bindings.contains { $0.projectID == model.selectedProject && $0.environment == model.environment && $0.variable == row.name } == true
                        HStack {
                            Text("\(row.id)").foregroundStyle(.secondary).frame(width: 24)
                            Text(row.name.isEmpty ? "잘못된 행" : row.name).font(.system(.caption, design: .monospaced))
                            Spacer()
                            Text(row.error ?? (conflict ? "기존 변수 · 충돌" : "새 변수 · ••••••••")).font(.caption).foregroundStyle(row.error != nil || conflict ? .orange : .secondary)
                        }.padding(10).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }.frame(height: 240)
            Toggle("충돌한 변수 연결을 새 키로 교체", isOn: $replace)
            Text("기본은 기존 유지입니다. 교체해도 다른 프로젝트의 공유 키는 변경하지 않습니다. 오류 행은 제외됩니다.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red) }
            HStack { Button("취소") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("유효한 \(rows.filter { $0.error == nil }.count)개 행 가져오기") { do { try model.importRows(rows, replace: replace); dismiss() } catch { self.error = error.localizedDescription } }.buttonStyle(.borderedProminent).disabled(!rows.contains { $0.error == nil }) }
        }.padding(28).frame(width: 650)
        .onDisappear { rows = [] }
    }
}
