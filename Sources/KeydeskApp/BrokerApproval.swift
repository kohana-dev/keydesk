import Foundation
import KeydeskCore

struct BrokerApproval: Identifiable, Sendable {
    let id = UUID()
    let request: BrokerRequest
    let channel: CLIChannel
    let grant: AccessGrant
    let projectName: String
}
