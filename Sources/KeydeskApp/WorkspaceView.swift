import SwiftUI
import KeydeskCore

struct WorkspaceView: View {
    @Bindable var model: VaultModel
    @State private var projectSheet = false
    @State private var addSheet = false
    @State private var importSheet = false
    @State private var recoverySheet = false
    @State private var activitySheet = false
    @State private var settingsSheet = false
    @State private var aiSheet = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar.frame(width: 215)
                Divider()
                keyList.frame(width: 330)
                Divider()
                DetailView(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let notice = model.notice {
                HStack { Image(systemName: "checkmark.circle"); Text(notice); Spacer(); Button("닫기", systemImage: "xmark") { model.notice = nil }.labelStyle(.iconOnly) }
                    .font(.callout).padding(12).background(Theme.accent.opacity(0.09))
            }
        }
        .background(.white)
        .sheet(isPresented: $projectSheet) { ProjectSheet(model: model) }
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
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Image(systemName: "key.horizontal.fill").foregroundStyle(.white).padding(9).background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
                Text("Keydesk").font(.title2.bold())
            }.padding(.top, 14)
            VStack(spacing: 6) {
                nav("모든 키", symbol: "square.grid.2x2", color: Theme.accent, selected: model.selectedProject == nil && !model.favoritesOnly) { model.selectedProject = nil; model.favoritesOnly = false }
                nav("즐겨찾기", symbol: "star", color: .orange, selected: model.favoritesOnly) { model.selectedProject = nil; model.favoritesOnly = true }
            }
            HStack { Text("프로젝트").font(.caption.bold()).foregroundStyle(.secondary); Spacer(); Button("프로젝트 추가", systemImage: "plus") { projectSheet = true }.labelStyle(.iconOnly) }
            VStack(spacing: 6) {
                ForEach(model.snapshot?.projects ?? []) { project in
                    nav(project.name, symbol: "folder", color: Theme.projectColors[abs(project.colorIndex % 3)], selected: model.selectedProject == project.id) { model.selectedProject = project.id; model.favoritesOnly = false }
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Button("암호화 백업", systemImage: "externaldrive.badge.timemachine") { saveBackup() }
                Button("복구 검증", systemImage: "arrow.counterclockwise") { recoverySheet = true }
                Button("활동 기록", systemImage: "clock.arrow.circlepath") { activitySheet = true }
                Button("AI 연결", systemImage: "sparkles") { aiSheet = true }
                Button("백업·CLI 설정", systemImage: "gearshape") { settingsSheet = true }
                Button("금고 잠금", systemImage: "lock") { model.lock() }
            }.buttonStyle(.plain)
            Divider()
            backupStatus
            Label(model.isDemo ? "데모 · 가상 키만 사용" : "이 Mac에 암호화 보관", systemImage: model.isDemo ? "testtube.2" : "shield.lefthalf.filled")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(maxHeight: .infinity).background(Theme.sidebar)
    }
    @ViewBuilder private var backupStatus: some View {
        if !model.isDemo {
            Button { settingsSheet = true } label: {
                if !model.recoveryKeySaved {
                    Label("복구 키 직접 보관 필요", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                } else if model.backupDirectory == nil {
                    Label("백업 폴더 없음", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                } else if model.backupFailure != nil {
                    Label("백업 실패", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                } else if model.hasUnbackedChanges {
                    Label("백업 대기 중", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.orange)
                } else if model.cloudUpload == .failed {
                    Label("iCloud 업로드 안 됨", systemImage: "exclamationmark.icloud").foregroundStyle(.red)
                } else if model.cloudUpload == .pending {
                    Label("iCloud 업로드 대기 중", systemImage: "icloud.and.arrow.up").foregroundStyle(.orange)
                } else if model.cloudUpload == .uploaded {
                    Label("iCloud까지 백업됨", systemImage: "checkmark.icloud").foregroundStyle(.green)
                } else {
                    Label("모든 변경 백업됨", systemImage: "checkmark.circle").foregroundStyle(.green)
                }
            }.buttonStyle(.plain).font(.caption.weight(.semibold)).help("백업 설정 열기")
        }
    }
    private func nav(_ title: String, symbol: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Image(systemName: symbol).foregroundStyle(color).frame(width: 22); Text(title).lineLimit(1); Spacer() }.padding(10).contentShape(Rectangle())
                .background(selected ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }
    private var keyList: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(model.selectedProject.flatMap { id in model.snapshot?.projects.first { $0.id == id }?.name } ?? (model.favoritesOnly ? "즐겨찾기" : "모든 키")).font(.title2.bold()); Spacer() }
            TextField("이름, 서비스, 계정 검색", text: $model.search).textFieldStyle(.roundedBorder)
            if model.selectedProject != nil {
                Picker("환경", selection: $model.environment) {
                    ForEach(EnvironmentName.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
                }.pickerStyle(.segmented)
                if model.environment == .production { Label("Production · 최초 승인 시 재인증", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            }
            HStack {
                Text("\(model.credentials.count)개 키").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.selectedProject != nil { Button(".env 가져오기", systemImage: "square.and.arrow.down") { importSheet = true }.labelStyle(.iconOnly).help(".env 가져오기") }
                Button("키 추가", systemImage: "plus") { addSheet = true }.buttonStyle(.borderedProminent)
            }
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(model.credentials) { credential in
                        Button { model.selectedCredential = credential.id; model.activity() } label: {
                            HStack(spacing: 12) {
                                ProviderIcon(provider: credential.provider)
                                VStack(alignment: .leading, spacing: 5) { Text(credential.name).font(.body.weight(.semibold)).lineLimit(1); Text(credential.provider).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                if credential.favorite { Image(systemName: "star.fill").foregroundStyle(.orange).font(.caption) }
                            }.padding(12).contentShape(Rectangle()).background(model.selectedCredential == credential.id ? Theme.accent.opacity(0.09) : Theme.canvas, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    }
                    if model.credentials.isEmpty { ContentUnavailableView("키가 없습니다", systemImage: "key", description: Text(model.search.isEmpty ? "키를 등록하거나 기존 키를 연결하세요." : "다른 검색어를 입력하세요.")) }
                }
            }
            Text(model.isDemo ? "데모 변경은 임시 금고에만 저장됩니다." : "개발 도구에는 keydesk run으로 선택한 키만 전달합니다.").font(.caption).foregroundStyle(.secondary)
        }.padding(22)
    }
    private func saveBackup() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Keydesk-backup-\(Date().formatted(.iso8601.year().month().day())).keydesk"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try model.backup(to: url) } catch { model.error = error.localizedDescription }
    }
}
