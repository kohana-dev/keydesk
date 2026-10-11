import Foundation
import Testing
@testable import KeydeskCore

struct ProjectDeletionTests {
    @Test func preservesSharedAndUnboundCredentialsAndOtherProjectExactly() throws {
        let test = Project(name: "test"), real = Project(name: "real")
        let exclusive = Credential(name: "exclusive", value: "FAKE1")
        let shared = Credential(name: "shared", value: "FAKE2")
        let unbound = Credential(name: "unbound", value: "FAKE3")
        var original = VaultSnapshot()
        original.projects = [test, real]; original.credentials = [exclusive, shared, unbound]
        original.bindings = [BindingRecord(projectID: test.id, environment: .development, variable: "EXCLUSIVE", credentialID: exclusive.id),
            BindingRecord(projectID: test.id, environment: .production, variable: "SHARED", credentialID: shared.id),
            BindingRecord(projectID: real.id, environment: .production, variable: "REAL_SHARED", credentialID: shared.id)]
        let result = try original.deletingProject("test")
        #expect(result.snapshot.projects == [real])
        #expect(result.snapshot.credentials.map(\.id) == [shared.id, unbound.id])
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        #expect(try encoder.encode(result.snapshot.credentials) == encoder.encode([shared, unbound]))
        #expect(try encoder.encode(result.snapshot.bindings) == encoder.encode([original.bindings[2]]))
        #expect(result.report.exclusiveCredentialsRemoved == 1)
        #expect(result.report.sharedCredentialsPreserved == 1 && result.report.unrelatedDataPreserved)
        #expect(original.credentials.count == 3)
    }

    @Test func rejectsMissingOrAmbiguousNamesAndAllowsExactUUID() throws {
        var original = VaultSnapshot()
        original.projects = [Project(name: "same"), Project(name: "same")]
        #expect(throws: (any Error).self) { try original.deletingProject("missing") }
        #expect(throws: (any Error).self) { try original.deletingProject("same") }
        let result = try original.deletingProject(original.projects[0].id.uuidString)
        #expect(result.snapshot.projects == [original.projects[1]])
        #expect(result.report.exclusiveCredentialsRemoved == 0)
    }
}
