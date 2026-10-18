import SwiftUI
import KeydeskCore
import UniformTypeIdentifiers

struct ProjectSheet: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Bindable var model: VaultModel
    var project: Project? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var iconPNG: Data?
    @State private var error: String?
    var body: some View {
        let _ = interfaceLanguage
        VStack(spacing: 0) {
            DialogCloseBar { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 16) {
                        ProjectAvatar(project: Project(name: name.isEmpty ? L10n.tr("프로젝트", "Project") : name, iconPNG: iconPNG), size: 64)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(project == nil ? L10n.tr("새 프로젝트", "New project") : L10n.tr("프로젝트 편집", "Edit project")).font(.title2.bold())
                            Text(L10n.tr("앱 아이콘으로 프로젝트를 쉽게 구분하세요.", "Use an app icon to recognize each project.")).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    TextField(L10n.tr("프로젝트 이름", "Project name"), text: $name).textFieldStyle(.roundedBorder)
                    HStack {
                        Button(iconPNG == nil ? L10n.tr("이미지 선택…", "Choose image…") : L10n.tr("이미지 변경…", "Change image…"), systemImage: "photo") { chooseImage() }
                        if iconPNG != nil { Button(L10n.tr("이미지 제거", "Remove image")) { iconPNG = nil } }
                    }
                    Text(L10n.tr("PNG · JPEG · HEIC · ICNS. 이미지는 작은 썸네일로 보관되며 암호화 백업에 포함됩니다.", "PNG · JPEG · HEIC · ICNS. Images are stored as small thumbnails and included in encrypted backups.")).font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red) }
                }.padding(28)
            }
            DialogFooter {
                DialogDismissButton(L10n.tr("취소", "Cancel"), prominent: false) { dismiss() }
                Spacer()
                Button(project == nil ? L10n.tr("만들기", "Create") : L10n.tr("저장", "Save")) {
                    do {
                        if let project { try model.updateProject(project.id, name: name, iconPNG: iconPNG) }
                        else { try model.addProject(name, iconPNG: iconPNG) }
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.frame(width: 480, height: DialogSizing.height(preferred: 420)).background(Theme.surface).foregroundStyle(Theme.ink)
            .onAppear { name = project?.name ?? ""; iconPNG = project?.iconPNG }
    }
    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .icns]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { iconPNG = try ProjectImage.load(url); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
