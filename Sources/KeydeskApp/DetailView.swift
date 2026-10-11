import SwiftUI
import KeydeskCore

struct DetailView: View {
    @Bindable var model: VaultModel
    @State private var rotating = false
    @State private var editing = false
    @State private var deleting = false
    @State private var unlinking = false
    var body: some View {
        if let credential = model.detail {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 13) {
                        ProviderIcon(provider: credential.provider)
                        VStack(alignment: .leading, spacing: 5) { Text(credential.name).font(.system(size: 23, weight: .semibold)); Text(credential.provider).foregroundStyle(.secondary) }
                        Spacer()
                        Button("즐겨찾기", systemImage: credential.favorite ? "star.fill" : "star") { model.toggleFavorite(credential.id) }.labelStyle(.iconOnly).foregroundStyle(.orange)
                        Button("정보 편집", systemImage: "pencil") { editing = true }.labelStyle(.iconOnly)
                    }
                    Label("제공사 상태 미확인", systemImage: "questionmark.circle").font(.caption).foregroundStyle(.secondary)
                    if let file = credential.currentFile {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("암호화 파일", systemImage: "doc.badge.lock").font(.headline)
                            Text(file.name).textSelection(.enabled)
                            Text("\(file.data.count)바이트 · 원본 바이트와 파일명 보존").font(.caption)
                            Text("keydesk run --files 변수명으로 실행 도구에 임시 파일 경로를 전달합니다. 실행 종료 시 삭제됩니다.").font(.caption).foregroundStyle(.secondary)
                            SecretFileReplacement(model: model, credential: credential)
                        }.padding(18).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.border, lineWidth: 0.5))
                    } else {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { Text("키 값").font(.headline); Spacer(); Text("보기 15초 · 복사 30초").font(.caption).foregroundStyle(.secondary) }
                        Text(model.revealID == credential.id ? model.revealedValue ?? "••••••••••••••••" : "••••••••••••••••••••••••")
                            .font(.system(.body, design: .monospaced)).lineLimit(5).privacySensitive()
                            .frame(maxWidth: .infinity, minHeight: 45, alignment: .leading).padding(12)
                            .background(.white, in: RoundedRectangle(cornerRadius: 8))
                        HStack {
                            Button(model.revealID == credential.id ? "숨기기" : "값 보기", systemImage: model.revealID == credential.id ? "eye.slash" : "eye") {
                                if model.revealID == credential.id { model.hideValue() } else { Task { await model.reveal(credential.id) } }
                            }
                            Button("키 복사", systemImage: "doc.on.doc") { Task { await model.copyValue(credential.id) } }.buttonStyle(.borderedProminent)
                            Spacer()
                            Button("키 교체", systemImage: "arrow.triangle.2.circlepath") { rotating = true }
                        }
                    }.padding(18).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.border, lineWidth: 0.5))
                    }
                    if !credential.account.isEmpty { field("발급 계정", credential.account) }
                    if !credential.note.isEmpty { field("메모", credential.note) }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("사용하는 프로젝트").font(.headline)
                        let bindings = model.snapshot?.bindings.filter { $0.credentialID == credential.id } ?? []
                        if bindings.isEmpty { Text("연결된 프로젝트가 없습니다.").foregroundStyle(.secondary) }
                        ForEach(bindings) { binding in
                            VStack(alignment: .leading, spacing: 9) {
                                HStack { Image(systemName: "folder").foregroundStyle(.secondary); Text(model.snapshot?.projects.first { $0.id == binding.projectID }?.name ?? ""); Spacer(); Text(binding.environment.title).font(.caption).foregroundStyle(binding.environment == .production ? .orange : .secondary) }
                                HStack { Text(binding.variable).font(.system(.caption, design: .monospaced)); Spacer(); Button("변수명 복사", systemImage: "doc.on.doc") { model.copyText(binding.variable) }.labelStyle(.iconOnly) }
                                HStack {
                                    Button("참조 복사") { model.copyText("keydesk://\(binding.projectID.uuidString)/\(binding.environment.rawValue)/\(binding.variable)") }
                                    Button("실행 명령 복사") { model.copyText("keydesk run --project \(binding.projectID.uuidString) --env \(binding.environment.rawValue) \(credential.currentFile == nil ? "--only" : "--files") \(binding.variable) -- npm run dev") }
                                }.font(.caption)
                            }.padding(14).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border, lineWidth: 0.5))
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("버전 이력 · \(credential.versions.count)개").font(.headline)
                        Text("이전 버전 복원은 새 로컬 버전을 만듭니다. 제공사에서 폐기된 키는 다시 활성화되지 않습니다.").font(.caption).foregroundStyle(.secondary)
                        ForEach(credential.versions) { version in
                            HStack {
                                Text(version.createdAt, format: .dateTime.year().month().day().hour().minute()).font(.caption)
                                Spacer()
                                if version.id == credential.currentVersionID { Text("현재").font(.caption.bold()).foregroundStyle(Theme.accent) }
                                else { Button("이 버전 복원") { do { try model.restoreVersion(credential.id, version: version) } catch { model.error = error.localizedDescription } }.font(.caption) }
                            }
                        }
                    }
                    Divider()
                    HStack {
                        if model.selectedProject != nil { Button("이 환경에서 연결 해제") { unlinking = true } }
                        Spacer()
                        Button("금고에서 삭제", role: .destructive) { deleting = true }
                    }
                    Text("삭제와 연결 해제는 제공사의 API 키를 폐기하지 않습니다. 과거 백업에는 값이 남을 수 있습니다.").font(.caption).foregroundStyle(.secondary)
                }.padding(32)
            }
            .id(credential.id)
            .sheet(isPresented: $rotating) { RotateView(model: model, credential: credential) }
            .sheet(isPresented: $editing) { MetadataView(model: model, credential: credential) }
            .confirmationDialog("금고에서 삭제할까요? 연결된 모든 프로젝트에서 제거됩니다. 제공사 폐기는 별도입니다.", isPresented: $deleting, titleVisibility: .visible) {
                Button("금고에서 삭제", role: .destructive) { do { try model.delete(credential.id) } catch { model.error = error.localizedDescription } }
            }
            .confirmationDialog("현재 프로젝트와 환경에서 연결을 해제할까요? 키는 금고에 남습니다.", isPresented: $unlinking, titleVisibility: .visible) {
                Button("연결 해제", role: .destructive) { do { try model.unlink(credential.id) } catch { model.error = error.localizedDescription } }
            }
        } else { ContentUnavailableView("키를 선택하세요", systemImage: "key.horizontal", description: Text("값과 사용처를 한곳에서 확인하세요.")) }
    }
    private func field(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).textSelection(.enabled) }
    }
}
