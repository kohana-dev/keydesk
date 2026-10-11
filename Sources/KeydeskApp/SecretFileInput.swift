import SwiftUI
import UniformTypeIdentifiers
import KeydeskCore

struct SecretFileInput: View {
    @Binding var file: SecretFile?
    @State private var importing = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(file?.name ?? "파일을 여기에 끌어 놓으세요", systemImage: "doc.badge.lock")
            if let file { Text("\(file.data.count)바이트 · 원본 그대로 암호화 보관").font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button(file == nil ? "파일 선택…" : "다른 파일 선택…") { importing = true }
                if file != nil { Button("선택 취소") { file = nil } }
            }
            Text("최대 1 MiB · .p8, .pem, JSON, .p12, .jks 등. 내용은 화면에 표시하지 않습니다.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 10))
        .dropDestination(for: URL.self) { urls, _ in
            guard urls.count == 1 else { error = "파일을 하나씩 선택해 주세요."; return false }
            return load(urls[0])
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url): _ = load(url)
            case .failure: error = "파일을 선택하지 못했습니다."
            }
        }
    }
    private func load(_ url: URL) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do { file = try SecretFile.read(at: url); error = nil; return true }
        catch { self.error = "파일을 읽지 못했습니다. 1 MiB 이하의 일반 파일을 선택해 주세요. 심볼릭 링크는 허용하지 않습니다."; return false }
    }
}
