import SwiftUI
import KeydeskCore

struct ImportView: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Bindable var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [DotenvRow] = []
    @State private var replace = false
    @State private var filename: String?
    @State private var error: String?
    var body: some View {
        let _ = interfaceLanguage
        let validRowCount = rows.filter { $0.error == nil }.count
        VStack(spacing: 0) {
            DialogCloseBar { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(L10n.tr(".env 가져오기 미리보기", "Preview .env import")).font(.title2.bold())
                    Text(L10n.tr("선택한 파일만 읽습니다. 값은 표시하지 않고 입력 구문은 실행하지 않습니다.", "Only the selected file is read. Values are hidden, and file contents are never executed.")).foregroundStyle(.secondary)
                    Button(filename ?? L10n.tr(".env 파일 선택", "Choose .env file"), systemImage: "doc") {
                        let panel = NSOpenPanel(); panel.showsHiddenFiles = true; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
                        guard panel.runModal() == .OK, let url = panel.url else { return }
                        do {
                            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                            guard let size = attributes[.size] as? NSNumber, size.intValue <= 1_048_576 else { throw VaultError.invalidData }
                            rows = DotenvParser.parse(try String(contentsOf: url, encoding: .utf8)); filename = url.lastPathComponent; error = nil
                        } catch { self.error = L10n.tr("파일을 읽지 못했습니다. UTF-8, 1MB 이하 파일을 선택하세요.", "Could not read the file. Choose a UTF-8 file no larger than 1 MiB.") }
                    }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(rows) { row in
                                let conflict = model.snapshot?.bindings.contains { $0.projectID == model.selectedProject && $0.environment == model.environment && $0.variable == row.name } == true
                                HStack {
                                    Text("\(row.id)").foregroundStyle(.secondary).frame(width: 24)
                                    Text(row.name.isEmpty ? L10n.tr("잘못된 행", "Invalid row") : row.name).font(.system(.caption, design: .monospaced))
                                    Spacer()
                                    Text(row.error ?? (conflict ? L10n.tr("기존 변수 · 충돌", "Existing variable · Conflict") : L10n.tr("새 변수 · ••••••••", "New variable · ••••••••"))).font(.caption).foregroundStyle(row.error != nil || conflict ? .orange : .secondary)
                                }.padding(10).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }.frame(height: 240)
                    Toggle(L10n.tr("충돌한 변수 연결을 새 키로 교체", "Replace conflicting variable connections with new keys"), isOn: $replace)
                    Text(L10n.tr("기본은 기존 유지입니다. 교체해도 다른 프로젝트의 공유 키는 변경하지 않습니다. 오류 행은 제외됩니다.", "Existing connections are kept by default. Replacing them does not change shared keys in other projects. Invalid rows are skipped.")).font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red) }
                }.padding(28)
            }
            DialogFooter { DialogDismissButton(L10n.tr("취소", "Cancel"), prominent: false) { dismiss() }; Spacer(); Button(L10n.tr("유효한 \(validRowCount)개 행 가져오기", validRowCount == 1 ? "Import 1 valid row" : "Import \(validRowCount) valid rows")) { do { try model.importRows(rows, replace: replace); dismiss() } catch { self.error = error.localizedDescription } }.buttonStyle(.borderedProminent).disabled(!rows.contains { $0.error == nil }) }
        }.frame(width: 650, height: DialogSizing.height(preferred: 572))
        .onDisappear { rows = [] }
    }
}
