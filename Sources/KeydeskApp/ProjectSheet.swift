import SwiftUI

struct ProjectSheet: View {
    @Bindable var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("프로젝트 만들기").font(.title2.bold())
            TextField("프로젝트 이름", text: $name).textFieldStyle(.roundedBorder)
            if let error { Text(error).foregroundStyle(.red) }
            HStack { Button("취소") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("만들기") { do { try model.addProject(name); dismiss() } catch { self.error = error.localizedDescription } }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
        }.padding(28).frame(width: 420)
    }
}
