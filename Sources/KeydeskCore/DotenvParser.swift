import Foundation

public enum DotenvParser {
    public static func parse(_ text: String) -> [DotenvRow] {
        let lines = text.components(separatedBy: .newlines)
        var rows = [DotenvRow](), seen = Set<String>(), index = 0
        while index < lines.count {
            let lineNumber = index + 1
            var line = lines[index].trimmingCharacters(in: .whitespaces); index += 1
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard let equals = line.firstIndex(of: "=") else {
                rows.append(DotenvRow(id: lineNumber, name: "", value: "", error: "변수명=값 형식이 필요합니다.")); continue
            }
            let name = String(line[..<equals]).trimmingCharacters(in: .whitespaces)
            var raw = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            var value = "", error: String?
            if let quote = raw.first, quote == "\"" || quote == "'" {
                var closed = false, escaped = false
                raw.removeFirst()
                while true {
                    var tail = ""
                    for char in raw {
                        if closed { tail.append(char); continue }
                        if escaped {
                            if quote == "\"" {
                                switch char {
                                case "n": value.append("\n")
                                case "r": value.append("\r")
                                case "t": value.append("\t")
                                case "\"", "\\": value.append(char)
                                default: value.append("\\"); value.append(char)
                                }
                            } else { value.append("\\"); value.append(char) }
                            escaped = false
                        } else if char == "\\" && quote == "\"" { escaped = true }
                        else if char == quote { closed = true }
                        else { value.append(char) }
                    }
                    if closed {
                        let trailing = tail.trimmingCharacters(in: .whitespaces)
                        if !trailing.isEmpty && !trailing.hasPrefix("#") { error = "따옴표 뒤의 내용을 확인하세요." }
                        break
                    }
                    guard index < lines.count else { error = "닫히지 않은 따옴표입니다."; break }
                    if escaped { value.append("\\"); escaped = false }
                    value.append("\n"); raw = lines[index]; index += 1
                }
            } else {
                if let range = raw.range(of: " #") { raw = String(raw[..<range.lowerBound]) }
                value = raw.trimmingCharacters(in: .whitespaces)
            }
            if !VaultSnapshot.validVariable(name) { error = "유효하지 않은 변수명입니다." }
            if !seen.insert(name).inserted { error = "파일 안에서 중복된 변수입니다." }
            if value.contains("\0") { error = "NUL 문자는 지원하지 않습니다." }
            if value.utf8.count > 65_536 { error = "값은 64KB 이하로 입력하세요." }
            rows.append(DotenvRow(id: lineNumber, name: name, value: value, error: error))
        }
        return rows
    }
}
