import SwiftUI
import KeydeskCore

struct LockedView: View {
    @Bindable var model: VaultModel
    @State private var recovering = false
    @State private var depositing = false
    @State private var recoveryURL: URL?
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "lock").font(.system(size: 36, weight: .light)).foregroundStyle(Theme.ink)
                .padding(24).background(.white, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border, lineWidth: 0.5))
            if model.exists || model.isDemo { lockedContent } else { firstRunContent }
            if model.busy { ProgressView().controlSize(.small) }
            Text("로컬 보관 · iCloud 암호화 백업 · CLI 연결").font(.caption).foregroundStyle(.secondary).padding(.top, 20)
        }
        .frame(maxWidth: 560).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.canvas)
        .task(id: model.exists) { if !model.exists { await model.prepareFirstRun() } }
        .sheet(isPresented: $depositing) { DepositView(model: model) }
        .sheet(isPresented: $recovering) { RecoveryView(model: model, initialURL: recoveryURL) }
    }
    @ViewBuilder private var lockedContent: some View {
        Text("금고가 잠겨 있습니다").font(.system(size: 28, weight: .semibold))
        Text("인증 후 프로젝트와 키를 확인할 수 있습니다.").foregroundStyle(.secondary)
        Button("금고 열기", systemImage: "touchid") { Task { await model.unlock() } }
            .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.busy)
        Button("새 키 맡기기", systemImage: "tray.and.arrow.down") { depositing = true }
        Button("백업 복구 검증", systemImage: "arrow.counterclockwise") { recoveryURL = nil; recovering = true }
    }
    @ViewBuilder private var firstRunContent: some View {
        switch model.firstRun {
        case .waitingForBackup:
            message("이전 금고의 백업을 기다리는 중", "iCloud 키체인에 이전 Keydesk 금고의 복구 키가 있습니다. iCloud Drive의 Keydesk 폴더가 이 Mac에 내려오면 그 금고를 복원합니다.")
            retryButtons(primary: "다시 확인")
        case .needsRecoveryCode(let url):
            message("iCloud 백업을 찾았습니다", "이 백업의 복구 키가 아직 이 Mac의 iCloud 키체인에 없습니다. 잠시 후 다시 확인하거나, 따로 보관한 복구 키를 입력하세요.")
            retryButtons(primary: "다시 확인", manual: url)
        case .restoreStopped(let url, let reason):
            message("복원을 마치지 못했습니다", reason)
            retryButtons(primary: "다시 복원", manual: url)
        case .failed(let reason):
            message("금고를 준비하지 못했습니다", reason)
            Button("다시 시도") { Task { await model.prepareFirstRun() } }.buttonStyle(.borderedProminent).controlSize(.large)
        case .checking, nil:
            message("금고를 준비하는 중", "iCloud Drive에서 기존 백업을 확인하고 없으면 새 금고를 만듭니다.")
        }
    }
    private func message(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.system(size: 28, weight: .semibold))
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }
    private func retryButtons(primary: String, manual: URL? = nil) -> some View {
        VStack(spacing: 12) {
            Button(primary) { Task { await model.prepareFirstRun() } }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.busy)
            HStack(spacing: 16) {
                if let manual { Button("복구 키 직접 입력") { recoveryURL = manual; recovering = true } }
                Button("새 금고로 시작") { Task { await model.prepareFirstRun(startNew: true) } }.disabled(model.busy)
            }
        }
    }
}
