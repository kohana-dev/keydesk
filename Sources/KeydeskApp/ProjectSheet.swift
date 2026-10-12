import SwiftUI
import KeydeskCore
import UniformTypeIdentifiers

struct ProjectSheet: View {
    @Bindable var model: VaultModel
    var project: Project? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var iconPNG: Data?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                ProjectAvatar(project: Project(name: name.isEmpty ? "프로젝트" : name, iconPNG: iconPNG), size: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text(project == nil ? "새 프로젝트" : "프로젝트 편집").font(.title2.bold())
                    Text("앱 아이콘으로 프로젝트를 쉽게 구분하세요.").font(.callout).foregroundStyle(.secondary)
                }
            }
            Divider()
            TextField("프로젝트 이름", text: $name).textFieldStyle(.roundedBorder)
            HStack {
                Button(iconPNG == nil ? "이미지 선택…" : "이미지 변경…", systemImage: "photo") { chooseImage() }
                if iconPNG != nil { Button("이미지 제거") { iconPNG = nil } }
            }
            Text("PNG · JPEG · HEIC · ICNS. 이미지는 작은 썸네일로 보관되며 암호화 백업에 포함됩니다.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(project == nil ? "만들기" : "저장") {
                    do {
                        if let project { try model.updateProject(project.id, name: name, iconPNG: iconPNG) }
                        else { try model.addProject(name, iconPNG: iconPNG) }
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(28).frame(width: 480).background(Theme.surface).foregroundStyle(Theme.ink)
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
