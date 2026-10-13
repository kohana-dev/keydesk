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
                CellarMark(size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cellar").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text(L10n.tr("개발 키 보관함", "Development key vault")).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.top, 10).padding(.bottom, 8)
            VStack(spacing: 6) {
                nav(L10n.tr("모든 키", "All keys"), symbol: "square.grid.2x2", color: Theme.ink, selected: model.selectedProject == nil && !model.favoritesOnly) { model.selectedProject = nil; model.favoritesOnly = false }
                nav(L10n.tr("즐겨찾기", "Favorites"), symbol: "star", color: .orange, selected: model.favoritesOnly) { model.selectedProject = nil; model.favoritesOnly = true }
            }
            HStack { Text(L10n.tr("프로젝트", "Projects")).font(.caption.bold()).foregroundStyle(.secondary); Spacer(); Button(L10n.tr("프로젝트 추가", "Add project"), systemImage: "plus") { projectSheet = true }.labelStyle(.iconOnly) }
            ScrollView {
            VStack(spacing: 4) {
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
            }.scrollIndicators(.hidden)
            VStack(alignment: .leading, spacing: 2) {
                nav(L10n.tr("AI 연결", "AI connections"), symbol: "terminal", color: Theme.violet, selected: false) { aiSheet = true }
                nav(L10n.tr("활동 기록", "Activity"), symbol: "clock.arrow.circlepath", color: .secondary, selected: false) { activitySheet = true }
                nav(L10n.tr("암호화 백업", "Encrypted backup"), symbol: "externaldrive.badge.timemachine", color: .secondary, selected: false) { saveBackup() }
                nav(L10n.tr("복구 검증", "Verify recovery"), symbol: "arrow.counterclockwise", color: .secondary, selected: false) { recoverySheet = true }
                nav(L10n.tr("백업·CLI 설정", "Backup & CLI"), symbol: "gearshape", color: .secondary, selected: false) { settingsSheet = true }
                nav(L10n.tr("금고 잠금", "Lock vault"), symbol: "lock", color: .secondary, selected: false) { model.lock() }
            }
            Divider()
            backupStatus
            Label(model.isDemo ? L10n.tr("데모 · 가상 키만 사용", "Demo · Sample keys only") : L10n.tr("이 Mac에 암호화 보관", "Encrypted on this Mac"), systemImage: model.isDemo ? "testtube.2" : "shield.lefthalf.filled")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(maxHeight: .infinity).background(Theme.sidebar)
    }
    @ViewBuilder private var backupStatus: some View {
        if !model.isDemo {
            Button { settingsSheet = true } label: {
                if !model.recoveryKeySaved {
                    Label(L10n.tr("복구 키 직접 보관 필요", "Save your recovery key"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                } else if model.backupDirectory == nil {
                    Label(L10n.tr("백업 폴더 없음", "No backup folder"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                } else if model.backupFailure != nil {
                    Label(L10n.tr("백업 실패", "Backup failed"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                } else if model.hasUnbackedChanges {
                    Label(L10n.tr("백업 대기 중", "Backup pending"), systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.orange)
                } else if model.cloudUpload == .failed {
                    Label(L10n.tr("iCloud 업로드 안 됨", "iCloud upload failed"), systemImage: "exclamationmark.icloud").foregroundStyle(.red)
                } else if model.cloudUpload == .pending {
                    Label(L10n.tr("iCloud 업로드 대기 중", "iCloud upload pending"), systemImage: "icloud.and.arrow.up").foregroundStyle(.orange)
                } else if model.cloudUpload == .uploaded {
                    Label(L10n.tr("iCloud까지 백업됨", "Backed up to iCloud"), systemImage: "checkmark.icloud").foregroundStyle(Theme.accent)
                } else {
                    Label(L10n.tr("모든 변경 백업됨", "All changes backed up"), systemImage: "checkmark.circle").foregroundStyle(Theme.accent)
                }
            }.buttonStyle(.plain).font(.caption.weight(.semibold)).help(L10n.tr("백업 설정 열기", "Open backup settings"))
        }
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
            Text(model.isDemo ? L10n.tr("데모 변경은 임시 금고에만 저장됩니다.", "Demo changes are saved only to a temporary vault.") : L10n.tr("개발 도구에는 keydesk run으로 선택한 키만 전달합니다.", "keydesk run passes only selected keys to your tools.")).font(.caption).foregroundStyle(.secondary)
        }.padding(20).background(Theme.surface)
    }
    private func saveBackup() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Cellar-backup-\(Date().formatted(.iso8601.year().month().day())).keydesk"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try model.backup(to: url) } catch { model.error = error.localizedDescription }
    }
}
