import Foundation
import Testing
import Darwin
import KeydeskCore
@testable import KeydeskApp

@Suite(.serialized)
struct FieldSelectionRunnerTests {
    private func fixture() -> (VaultSnapshot, UUID) {
        let project = Project(name: "Synthetic field delivery")
        let document = Credential(name: "Synthetic bundle", value: "{\"token\":\"FICTIONAL_SELECTED_TOKEN\",\"other\":\"FICTIONAL_UNSELECTED_TOKEN\",\"nested\":{\"port\":9007199254740993}}", format: .json)
        let other = Credential(name: "Unselected key", value: "FICTIONAL_OTHER_API_KEY")
        var snapshot = VaultSnapshot(); snapshot.projects = [project]; snapshot.credentials = [document, other]
        snapshot.bindings = [BindingRecord(projectID: project.id, environment: .development, variable: "CONFIG", credentialID: document.id), BindingRecord(projectID: project.id, environment: .development, variable: "UNRELATED_KEY", credentialID: other.id)]
        return (snapshot, project.id)
    }

    @Test func pipeAndPTYReceiveOnlySelectedFieldsAndMaskTheirOutput() async throws {
        let (snapshot, project) = fixture()
        for interactive in [false, true] {
            let selections = [try SecretFieldSelection.parse("TOKEN=CONFIG#/token"), try SecretFieldSelection.parse("PORT=CONFIG#/nested/port")]
            let command = "test -z \"${CONFIG+x}\" && test -z \"${UNRELATED_KEY+x}\" && test -z \"${other+x}\" && test \"$TOKEN\" = FICTIONAL_SELECTED_TOKEN && test \"$PORT\" = 9007199254740993 || exit 91; printf '%s:%s\\n' \"$TOKEN\" \"$PORT\""
            let request = CLIRequest(project: project.uuidString, environment: .development, command: ["/bin/sh", "-c", command], directory: "/tmp", stdinKey: nil, interactive: interactive, selections: selections)
            let available = try snapshot.environment(projectID: project, environment: .development, selections: selections)
            let (channel, client) = try RunnerTests().sockets(); defer { close(client); channel.finish() }
            let running = try await BlockingRunnerTestSupport.start(request, secrets: available, channel: channel)
            defer { running.terminate() }
            var output = Data(), exit: Int32?
            while let line = try await BlockingRunnerTestSupport.readLine(from: client) {
                let event = try JSONDecoder().decode(CLIEvent.self, from: line)
                if let data = event.data { output += data }
                if event.kind == "exit" { exit = event.exitCode; break }
            }
            #expect(exit == 0)
            let text = String(decoding: output, as: UTF8.self)
            #expect(text.contains("[REDACTED]:[REDACTED]") && !text.contains("FICTIONAL_") && !text.contains("9007199254740993"))
        }
    }

    @Test func selectedDocumentStringCanUseStdinWithoutEnvironmentCopy() async throws {
        let (snapshot, project) = fixture(), selection = try SecretFieldSelection.parse("TOKEN=CONFIG#/token")
        let request = CLIRequest(project: project.uuidString, environment: .development, command: ["/bin/sh", "-c", "test -z \"${TOKEN+x}\" && test -z \"${CONFIG+x}\" && test -z \"${UNRELATED_KEY+x}\" || exit 91; read value; test \"$value\" = FICTIONAL_SELECTED_TOKEN || exit 92; printf 'SELECTED_STDIN_OK\\n'"], directory: "/tmp", stdinKey: "TOKEN", selections: [selection])
        let (channel, client) = try RunnerTests().sockets(); defer { close(client); channel.finish() }
        let running = try await BlockingRunnerTestSupport.start(request, secrets: snapshot.environment(projectID: project, environment: .development, selections: [selection]), channel: channel)
        defer { running.terminate() }
        var output = Data(), exit: Int32?
        while let line = try await BlockingRunnerTestSupport.readLine(from: client) {
            let event = try JSONDecoder().decode(CLIEvent.self, from: line)
            if let data = event.data { output += data }
            if event.kind == "exit" { exit = event.exitCode; break }
        }
        #expect(exit == 0 && String(decoding: output, as: UTF8.self).contains("SELECTED_STDIN_OK"))
    }

    @Test func commandGrantBindsSourcePathAndOutput() throws {
        let executable = try ExecutableIdentity.capture(command: "/usr/bin/true", directory: "/tmp")
        func request(_ field: SecretFieldSelection) -> CLIRequest {
            CLIRequest(project: "fixture", environment: .development, command: ["/usr/bin/true"], directory: "/tmp", stdinKey: nil, selections: [field])
        }
        let original = request(try SecretFieldSelection.parse("TOKEN=CONFIG#/token"))
        var cache = DevelopmentApprovalCache(); try cache.remember(original, executable: executable)
        #expect(cache.allows(original, executable: executable))
        for field in ["TOKEN=CONFIG#/other", "TOKEN=OTHER#/token", "RENAMED=CONFIG#/token"] {
            #expect(!cache.allows(request(try SecretFieldSelection.parse(field)), executable: executable))
        }
    }
}
