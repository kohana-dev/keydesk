import Foundation
import KeydeskCore

struct APIApproval: Identifiable, Sendable {
    let id = UUID()
    let request: APIRequest
    let projectName: String
    let credentialName: String
    let format: SecretFormat
    let credentialID: UUID
    let versionID: UUID
    let provider: APIProvider
    let channel: CLIChannel
}
