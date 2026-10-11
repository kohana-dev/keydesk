import Foundation

/// Conservative IPv4-only egress. IPv6-only destinations are unsupported, not silently unchecked.
public enum PublicIPv4 {
    public static func allowed(_ address: String) -> Bool {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ $0 == "0" || !$0.hasPrefix("0") }),
              parts.allSatisfy({ UInt8($0) != nil }) else { return false }
        let p = parts.map { Int($0)! }, a = p[0], b = p[1], c = p[2]
        if a == 0 || a == 10 || a == 127 || a >= 224 { return false }
        if a == 100 && (64...127).contains(b) { return false }
        if a == 169 && b == 254 || a == 172 && (16...31).contains(b) || a == 192 && b == 168 { return false }
        if a == 192 && b == 0 && (c == 0 || c == 2) || a == 192 && b == 88 && c == 99 { return false }
        if a == 198 && (b == 18 || b == 19) || a == 198 && b == 51 && c == 100 || a == 203 && b == 0 && c == 113 { return false }
        return true
    }
}
