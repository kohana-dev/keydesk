import SwiftUI

struct ContentView: View {
    @Bindable var model: VaultModel
    var body: some View {
        Group {
            if model.snapshot == nil { LockedView(model: model) }
            else { WorkspaceView(model: model) }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.light)
        .alert("작업을 완료하지 못했습니다", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("확인") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
