import Foundation

public struct ProjectDeletionReport: Codable, Sendable {
    public let projectsRemoved: Int
    public let bindingsRemoved: Int
    public let exclusiveCredentialsRemoved: Int
    public let sharedCredentialsPreserved: Int
    public let unrelatedDataPreserved: Bool
}

extension VaultSnapshot {
    /// Removes only credentials referenced by this project and no remaining project.
    /// Unbound credentials and credentials shared with other projects are preserved.
    public func deletingProject(_ nameOrID: String) throws -> (snapshot: Self, report: ProjectDeletionReport) {
        let matches = projects.filter { $0.name == nameOrID || $0.id.uuidString.lowercased() == nameOrID.lowercased() }
        guard matches.count == 1, let target = matches.first else { throw VaultError.invalidData }
        let removedBindings = bindings.filter { $0.projectID == target.id }
        let candidateIDs = Set(removedBindings.map(\.credentialID))
        let retainedBindings = bindings.filter { $0.projectID != target.id }
        let retainedIDs = Set(retainedBindings.map(\.credentialID))
        let exclusiveIDs = candidateIDs.subtracting(retainedIDs)
        var next = self
        next.projects.removeAll { $0.id == target.id }
        next.bindings = retainedBindings
        next.credentials.removeAll { exclusiveIDs.contains($0.id) }
        next = try next.validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let preserved = try encoder.encode(next.credentials) == encoder.encode(credentials.filter { !exclusiveIDs.contains($0.id) })
            && encoder.encode(next.projects) == encoder.encode(projects.filter { $0.id != target.id })
            && encoder.encode(next.bindings) == encoder.encode(retainedBindings)
        guard preserved else { throw VaultError.invalidData }
        return (next, ProjectDeletionReport(projectsRemoved: 1, bindingsRemoved: removedBindings.count,
            exclusiveCredentialsRemoved: exclusiveIDs.count,
            sharedCredentialsPreserved: candidateIDs.intersection(retainedIDs).count,
            unrelatedDataPreserved: preserved))
    }
}
