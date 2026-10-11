import Foundation

public enum APIRequestParser {
    public static func parse(_ args: [String], bodyReader: (String) throws -> String) throws -> APIRequest {
        var fields: [String: String] = [:], i = 0
        let allowed: Set<String> = ["--project", "--env", "--key", "--method", "--url", "--body-file"]
        while i < args.count {
            guard i + 1 < args.count, allowed.contains(args[i]), fields[args[i]] == nil else { throw VaultError.invalidData }
            fields[args[i]] = args[i+1]; i += 2
        }
        guard let project = fields["--project"], let variable = fields["--key"], let url = fields["--url"],
              let environment = EnvironmentName(rawValue: fields["--env"] ?? "dev") else { throw VaultError.invalidData }
        let body = try fields["--body-file"].map(bodyReader)
        let result = APIRequest(project: project, environment: environment, variable: variable, method: fields["--method"] ?? "GET", url: url, body: body)
        _ = try result.validated(); return result
    }
}
