import SwiftUI
import KeydeskCore

struct DetailView: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Bindable var model: VaultModel
    @State private var rotating = false
    @State private var editing = false
    @State private var deleting = false
    @State private var unlinking = false
    var body: some View {
        let _ = interfaceLanguage
        if let credential = model.detail {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 13) {
                        SecretItemIcon(credential: credential)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(credential.name).font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.ink)
                            if !credential.provider.isEmpty, credential.provider != "Other" {
                                Text(credential.provider).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(L10n.tr("즐겨찾기", "Favorites"), systemImage: credential.favorite ? "star.fill" : "star") { model.toggleFavorite(credential.id) }.labelStyle(.iconOnly).foregroundStyle(.orange)
                        Button(L10n.tr("정보 편집", "Edit details"), systemImage: "pencil") { editing = true }.labelStyle(.iconOnly)
                    }
                    HStack(spacing: 12) {
                        SecretFormatBadge(format: credential.currentFormat)
                        Label(L10n.tr("암호화 보관", "Stored encrypted"), systemImage: "lock.shield")
                            .font(.caption).foregroundStyle(.secondary)
                        if credential.currentFormat == .apiKey {
                            Label(L10n.tr("제공사 상태 미확인", "Provider status not checked"), systemImage: "questionmark.circle").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let file = credential.currentFile {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(L10n.tr("암호화 파일", "Encrypted file"), systemImage: "doc.badge.lock").font(.headline)
                            Text(file.name).textSelection(.enabled)
                            Text(L10n.tr("\(file.data.count)바이트 · 원본 바이트와 파일명 보존", "\(file.data.count) bytes · Original contents and filename preserved")).font(.caption)
                            Text(L10n.tr("keydesk run --files 변수명으로 실행 도구에 임시 파일 경로를 전달합니다. 실행 종료 시 삭제됩니다.", "Use keydesk run --files VARIABLE to pass a temporary file path to a tool. The file is deleted when the command exits.")).font(.caption).foregroundStyle(.secondary)
                            SecretFileReplacement(model: model, credential: credential)
                        }.padding(20).cellarCard()
                    } else {
                        SecretValueCard(model: model, credential: credential) { rotating = true }
                    }
                    if !credential.account.isEmpty { field(L10n.tr("발급 계정", "Account"), credential.account) }
                    if !credential.note.isEmpty { field(L10n.tr("메모", "Note"), credential.note) }
                    VStack(alignment: .leading, spacing: 12) {
                        Label(L10n.tr("사용하는 프로젝트", "Connected projects"), systemImage: "folder").font(.headline)
                        if credential.currentFormat != .apiKey, credential.currentFormat != .file {
                            Text(L10n.tr("프로젝트별로 정리하고 참조할 수 있습니다. 이 내용은 CLI 실행이나 API 요청에 자동으로 전달되지 않습니다.", "Organize and reference this item by project. These contents are not passed automatically to CLI commands or API requests."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        let bindings = model.snapshot?.bindings.filter { $0.credentialID == credential.id } ?? []
                        if bindings.isEmpty { Text(L10n.tr("연결된 프로젝트가 없습니다.", "No connected projects.")).foregroundStyle(.secondary) }
                        ForEach(bindings) { binding in
                            VStack(alignment: .leading, spacing: 9) {
                                HStack { if let project = model.snapshot?.projects.first(where: { $0.id == binding.projectID }) { ProjectAvatar(project: project, size: 24); Text(project.name) }; Spacer(); Text(binding.environment.title).font(.caption).foregroundStyle(binding.environment == .production ? .orange : .secondary) }
                                HStack { Text(binding.variable).font(.system(.caption, design: .monospaced)); Spacer(); Button(L10n.tr("변수명 복사", "Copy variable name"), systemImage: "doc.on.doc") { model.copyText(binding.variable) }.labelStyle(.iconOnly) }
                                HStack {
                                    Button(L10n.tr("참조 복사", "Copy reference")) { model.copyText("keydesk://\(binding.projectID.uuidString)/\(binding.environment.rawValue)/\(binding.variable)") }
                                    if credential.currentFormat == .apiKey || credential.currentFormat == .file {
                                        Button(L10n.tr("실행 명령 복사", "Copy run command")) { model.copyText("keydesk run --project \(binding.projectID.uuidString) --env \(binding.environment.rawValue) \(credential.currentFile == nil ? "--only" : "--files") \(binding.variable) -- npm run dev") }
                                    }
                                }.font(.caption)
                            }.padding(16).cellarCard()
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Label(L10n.tr("버전 이력 · \(credential.versions.count)개", "Version history · \(credential.versions.count)"), systemImage: "clock.arrow.circlepath").font(.headline)
                        Text(credential.currentFormat == .apiKey
                             ? L10n.tr("이전 버전 복원은 새 로컬 버전을 만듭니다. 제공사에서 폐기된 키는 다시 활성화되지 않습니다.", "Restoring a version creates a new local version. It does not reactivate a key revoked by the provider.")
                             : L10n.tr("이전 내용과 형식을 새 로컬 버전으로 복원합니다. 기존 이력도 유지됩니다.", "Restore earlier contents and their format as a new local version. Existing history is preserved."))
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(credential.versions) { version in
                            HStack {
                                Text(version.createdAt, format: .dateTime.year().month().day().hour().minute().locale(L10n.locale)).font(.caption)
                                SecretFormatBadge(format: version.format)
                                Spacer()
                                if version.id == credential.currentVersionID { Text(L10n.tr("현재", "Current")).font(.caption.bold()).foregroundStyle(Theme.accent) }
                                else { Button(L10n.tr("이 버전 복원", "Restore this version")) { do { try model.restoreVersion(credential.id, version: version) } catch { model.error = error.localizedDescription } }.font(.caption) }
                            }
                        }
                    }.padding(20).cellarCard()
                    Divider()
                    HStack {
                        if model.selectedProject != nil { Button(L10n.tr("이 환경에서 연결 해제", "Disconnect from this environment")) { unlinking = true } }
                        Spacer()
                        Button(L10n.tr("금고에서 삭제", "Delete from vault"), role: .destructive) { deleting = true }
                    }
                    Text(credential.currentFormat == .apiKey
                         ? L10n.tr("삭제와 연결 해제는 제공사의 API 키를 폐기하지 않습니다. 과거 백업에는 값이 남을 수 있습니다.", "Deleting or disconnecting a key does not revoke it with the provider. Older backups may still contain its value.")
                         : L10n.tr("삭제한 항목의 내용이 과거 백업에는 남아 있을 수 있습니다.", "Older backups may still contain a deleted item's contents."))
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(30)
            }
            .background(Theme.canvas)
            .id(credential.id)
            .sheet(isPresented: $rotating) { RotateView(model: model, credential: credential) }
            .sheet(isPresented: $editing) { MetadataView(model: model, credential: credential) }
            .confirmationDialog(L10n.tr("금고에서 삭제할까요? 연결된 모든 프로젝트에서도 이 항목이 제거됩니다.", "Delete from the vault? This removes the item from every connected project."), isPresented: $deleting, titleVisibility: .visible) {
                Button(L10n.tr("금고에서 삭제", "Delete from vault"), role: .destructive) { do { try model.delete(credential.id) } catch { model.error = error.localizedDescription } }
            }
            .confirmationDialog(L10n.tr("현재 프로젝트와 환경에서 연결을 해제할까요? 항목은 금고에 남습니다.", "Disconnect from this project and environment? The item stays in the vault."), isPresented: $unlinking, titleVisibility: .visible) {
                Button(L10n.tr("연결 해제", "Disconnect"), role: .destructive) { do { try model.unlink(credential.id) } catch { model.error = error.localizedDescription } }
            }
        } else {
            VStack(spacing: 14) {
                CellarMark(size: 88)
                Text(L10n.tr("항목을 선택하세요", "Select an item")).font(.title2.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(L10n.tr("암호화한 키, 문서, 파일을 한곳에서 확인하세요.", "View your encrypted keys, documents, and files in one place.")).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.canvas)
        }
    }
    private func field(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).textSelection(.enabled) }
    }
}
