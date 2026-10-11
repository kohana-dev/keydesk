import SwiftUI
import KeydeskCore

struct ProviderPicker: View {
    @Binding private var provider: String
    @State private var query: String
    @State private var expanded = false
    @State private var browseAll = false
    @State private var highlighted: String?
    @FocusState private var focused: Bool
    init(provider: Binding<String>) {
        _provider = provider
        _query = State(initialValue: provider.wrappedValue)
    }
    private var matches: [ProviderCatalog.Category] { ProviderCatalog.matching(browseAll ? "" : query) }
    private var names: [String] { matches.flatMap(\.providers) }
    private func select(_ name: String) {
        query = name; provider = name; expanded = false; browseAll = false; highlighted = nil; focused = false
    }
    private func move(_ delta: Int) {
        expanded = true
        let results = names
        guard !results.isEmpty else { return }
        let current = highlighted.flatMap { results.firstIndex(of: $0) } ?? (delta > 0 ? -1 : results.count)
        highlighted = results[min(max(current + delta, 0), results.count - 1)]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("서비스").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ProviderLogo(provider: provider, size: 20)
                TextField("서비스 검색 또는 직접 입력", text: Binding(get: { query }, set: {
                    guard query != $0 else { return }
                    query = $0; provider = $0; expanded = true; browseAll = false; highlighted = nil
                }))
                .textFieldStyle(.plain).focused($focused)
                .onKeyPress(.return) {
                    if let name = highlighted ?? names.first { select(name) }
                    else { select(query.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    return .handled
                }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.escape) { expanded = false; return .handled }
                if !query.isEmpty {
                    Button { query = ""; provider = ""; expanded = true; browseAll = true; highlighted = nil; focused = true } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain).accessibilityLabel("서비스 검색 지우기")
                }
                Button {
                    let opening = !(expanded && focused)
                    browseAll = opening; expanded = opening; focused = opening
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }.buttonStyle(.plain).accessibilityLabel("서비스 추천 목록")
            }
            .padding(9).background(.white, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.gray.opacity(0.3)))
            if expanded && focused {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(matches) { category in
                                Text(category.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    .padding(.horizontal, 10).padding(.top, 8)
                                ForEach(category.providers, id: \.self) { name in
                                    Button { select(name) } label: {
                                        HStack(spacing: 10) {
                                            ProviderLogo(provider: name, size: 20)
                                            Text(name == "Other" ? "기타" : name).foregroundStyle(.primary)
                                            Spacer()
                                            if name == provider { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                                        }.padding(.horizontal, 10).padding(.vertical, 6).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain).id(name)
                                    .background(highlighted == name ? Theme.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 5))
                                    .accessibilityLabel("서비스 선택: \(name)")
                                }
                            }
                            let custom = query.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !custom.isEmpty && !ProviderName.options.contains(where: { $0.caseInsensitiveCompare(custom) == .orderedSame }) {
                                Divider().padding(.vertical, 4)
                                Button("‘\(custom)’ 직접 입력") { select(custom) }
                                    .buttonStyle(.plain).padding(10)
                            }
                            if matches.isEmpty { Text("일치하는 서비스가 없습니다. 입력한 이름을 사용할 수 있습니다.").font(.caption).foregroundStyle(.secondary).padding(10) }
                        }.padding(4)
                    }
                    .frame(maxHeight: 220)
                    .onChange(of: highlighted) { if let highlighted { proxy.scrollTo(highlighted, anchor: .center) } }
                }
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.2)))
            }
        }
        .onChange(of: focused) { expanded = focused }
    }
}
