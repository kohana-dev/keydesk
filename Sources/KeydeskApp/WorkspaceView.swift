import SwiftUI
import KeydeskCore

struct WorkspaceView: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Bindable var model: VaultModel
    @State private var projectSheet = false
    @State private var editingProject: Project?
    @State private var addSheet = false
    @State private var importSheet = false
    @State private var recoverySheet = false
    @State private var activitySheet = false
    @State private var settingsSheet = false
    @State private var aiSheet = false
    var body: some View {
        let _ = interfaceLanguage
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar.frame(width: 220)
                Divider()
                keyList.frame(width: 340)
                Divider()
                DetailView(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let notice = model.notice {
                HStack { Image(systemName: "checkmark.circle"); Text(notice); Spacer(); Button(L10n.tr("닫기", "Close"), systemImage: "xmark") { model.notice = nil }.labelStyle(.iconOnly) }
                    .font(.callout).padding(12).background(Theme.accent.opacity(0.09))
            }
        }
        .background(Theme.canvas)
        .sheet(isPresented: $projectSheet) { ProjectSheet(model: model) }
        .sheet(item: $editingProject) { ProjectSheet(model: model, project: $0) }
        .sheet(isPresented: $addSheet) { CredentialSheet(model: model) }
        .sheet(isPresented: $importSheet) { ImportView(model: model) }
        .sheet(isPresented: $recoverySheet) { RecoveryView(model: model) }
        .sheet(isPresented: $activitySheet) { ActivityView(model: model) }
        .sheet(isPresented: $settingsSheet) { SettingsView(model: model) }
        .sheet(isPresented: $aiSheet) { AIConnectionsView(model: model) }
        .onChange(of: model.selectedCredential) { model.hideValue() }
        .onChange(of: model.selectedProject) { model.selectedCredential = nil; model.hideValue() }
        .onChange(of: model.environment) { model.selectedCredential = nil; model.hideValue() }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                CellarMark(size: 32)
                Text("Cellar").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.ink)
            }.padding(.top, 6).padding(.bottom, 4)
            VStack(spacing: 6) {
                nav(L10n.tr("모든 키", "All keys"), symbol: "square.grid.2x2", color: Theme.ink, selected: model.selectedProject == nil && !model.favoritesOnly) { model.selectedProject = nil; model.favoritesOnly = false }
                nav(L10n.tr("즐겨찾기", "Favorites"), symbol: "star", color: .orange, selected: model.favoritesOnly) { model.selectedProject = nil; model.favoritesOnly = true }
            }
            HStack {
                Text(L10n.tr("프로젝트", "Projects")).font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.tr("프로젝트 추가", "Add project"), systemImage: "plus") { projectSheet = true }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("sidebar-add-project")
            }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.snapshot?.projects ?? []) { project in
                        Button { model.selectedProject = project.id; model.favoritesOnly = false } label: {
                            HStack(spacing: 10) {
                                ProjectAvatar(project: project)
                                Text(project.name).font(.system(size: 13, weight: model.selectedProject == project.id ? .semibold : .regular)).lineLimit(1)
                                Spacer()
                            }.padding(.horizontal, 9).padding(.vertical, 7)
                                .contentShape(Rectangle())
                                .background(model.selectedProject == project.id ? Theme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).contextMenu {
                            Button(L10n.tr("프로젝트 편집…", "Edit project…"), systemImage: "pencil") { editingProject = project }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .accessibilityIdentifier("sidebar-project-list")
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                SidebarBackupNotice(model: model) { settingsSheet = true }
                HStack(spacing: 8) {
                    SidebarToolsMenu(
                        backupStatus: model.menuBarBackupStatus,
                        openSettings: { settingsSheet = true },
                        openAIConnections: { aiSheet = true },
                        openActivity: { activitySheet = true },
                        exportBackup: { saveBackup() },
                        verifyRecovery: { recoverySheet = true }
                    )
                    Button(L10n.tr("금고 잠금", "Lock vault"), systemImage: "lock") { model.lock() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("sidebar-lock-vault")
                        .help(L10n.tr("금고 잠금", "Lock vault"))
                }
            }
        }.padding(18).frame(maxHeight: .infinity).background(Theme.sidebar)
    }
    private func nav(_ title: String, symbol: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Image(systemName: symbol).foregroundStyle(selected ? Theme.accent : color).frame(width: 22); Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular)).lineLimit(1); Spacer() }.padding(.horizontal, 10).padding(.vertical, 9).contentShape(Rectangle())
                .foregroundStyle(selected ? Theme.ink : .primary)
                .background(selected ? Theme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }
    private var keyList: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                if let project = model.snapshot?.projects.first(where: { $0.id == model.selectedProject }) {
                    ProjectAvatar(project: project, size: 32)
                    Text(project.name).font(.system(size: 21, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Button(L10n.tr("프로젝트 편집", "Edit project"), systemImage: "ellipsis") { editingProject = project }.labelStyle(.iconOnly).buttonStyle(.plain).help(L10n.tr("이름 및 이미지 변경", "Change name and image"))
                } else {
                    Text(model.favoritesOnly ? L10n.tr("즐겨찾기", "Favorites") : L10n.tr("모든 키", "All keys")).font(.system(size: 21, weight: .semibold))
                    Spacer()
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L10n.tr("이름, 서비스, 계정 검색", "Search name, service, or account"), text: $model.search).textFieldStyle(.plain)
                if !model.search.isEmpty { Button(L10n.tr("검색 지우기", "Clear search"), systemImage: "xmark.circle.fill") { model.search = "" }.labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary) }
            }.padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border, lineWidth: 0.7))
            if model.selectedProject != nil {
                Picker(L10n.tr("환경", "Environment"), selection: $model.environment) {
                    ForEach(EnvironmentName.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
                }.pickerStyle(.segmented)
                if model.environment == .production { Label(L10n.tr("Production · 최초 승인 시 재인증", "Production · Re-authenticate on first approval"), systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            }
            HStack {
                Text(L10n.tr("\(model.credentials.count)개 키", model.credentials.count == 1 ? "1 key" : "\(model.credentials.count) keys")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.selectedProject != nil { Button(L10n.tr(".env 가져오기", "Import .env"), systemImage: "square.and.arrow.down") { importSheet = true }.labelStyle(.iconOnly).help(L10n.tr(".env 가져오기", "Import .env")) }
                Button(L10n.tr("키 추가", "Add key"), systemImage: "plus") { addSheet = true }.buttonStyle(.borderedProminent)
            }
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(model.credentials) { credential in
                        Button { model.selectedCredential = credential.id; model.activity() } label: {
                            HStack(spacing: 12) {
                                ProviderIcon(provider: credential.provider)
                                VStack(alignment: .leading, spacing: 5) { Text(credential.name).font(.system(size: 13, weight: .semibold)).lineLimit(1); Text(credential.provider + (credential.currentFile == nil ? L10n.tr(" · API 키", " · API key") : L10n.tr(" · 파일", " · File"))).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                if credential.favorite { Image(systemName: "star.fill").foregroundStyle(.orange).font(.caption) }
                            }.padding(.horizontal, 12).padding(.vertical, 11).contentShape(Rectangle())
                                .background(model.selectedCredential == credential.id ? Theme.selection : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(model.selectedCredential == credential.id ? Theme.accent.opacity(0.25) : Theme.border.opacity(0.65), lineWidth: 0.7))
                        }.buttonStyle(.plain)
                    }
                    if model.credentials.isEmpty { ContentUnavailableView(L10n.tr("키가 없습니다", "No keys"), systemImage: "key", description: Text(model.search.isEmpty ? L10n.tr("키를 등록하거나 기존 키를 연결하세요.", "Add a key or connect an existing one.") : L10n.tr("다른 검색어를 입력하세요.", "Try a different search."))) }
                }
            }
            if model.isDemo {
                Text(L10n.tr("데모 변경은 임시 금고에만 저장됩니다.", "Demo changes are saved only to a temporary vault.")).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(20).background(Theme.surface)
    }
    private func saveBackup() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Cellar-backup-\(Date().formatted(.iso8601.year().month().day())).keydesk"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try model.backup(to: url) } catch { model.error = error.localizedDescription }
    }
}
