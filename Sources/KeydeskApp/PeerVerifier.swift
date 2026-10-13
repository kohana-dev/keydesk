import Foundation
import Security
import Darwin
import KeydeskCore

// Authenticate the direct socket peer, not the AI/editor that launched the CLI.
enum PeerVerifier {
    // Immutable Security requirement shared with the socket's serial accept queue.
    final class Requirement: @unchecked Sendable {
        let value: SecRequirement
        init(_ value: SecRequirement) { self.value = value }
    }
    static func requirement(for executable: URL) throws -> Requirement {
        var code: SecStaticCode?, requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(executable as CFURL, [], &code) == errSecSuccess,
              let code, SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess,
              SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess,
              let requirement else { throw NSError(domain: "Keydesk", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.tr("내장 CLI 서명을 확인하지 못했습니다.", "The bundled CLI signature could not be verified.")]) }
        return Requirement(requirement)
    }
    static func matches(pid: pid_t, requirement: Requirement) -> Bool {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: pid)]
        return SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, [], &code) == errSecSuccess && code != nil &&
            SecCodeCheckValidity(code!, SecCSFlags(rawValue: kSecCSStrictValidate), requirement.value) == errSecSuccess
    }
    static func pid(for socket: Int32) throws -> pid_t {
        var pid: pid_t = 0, size = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(socket, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0, pid > 0 else { throw VaultError.accessDenied }
        return pid
    }
}
