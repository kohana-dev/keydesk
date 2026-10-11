import Foundation
import KeydeskCore

struct CLIApproval: Identifiable, Sendable {
    let id = UUID()
    let request: CLIRequest
    let channel: CLIChannel
    let executable: ExecutableIdentity
    init(request: CLIRequest, channel: CLIChannel) throws {
        self.request = request; self.channel = channel
        executable = try ExecutableIdentity.capture(command: request.command.first ?? "", directory: request.directory)
    }
}
