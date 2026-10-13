# Cellar

A local macOS vault for developers and their AI tools. Keep API keys and original key files organized by project, and let Codex, Claude and CLI tools use selected credentials through an approved local broker.

개인 개발자를 위한 macOS 로컬 키 금고입니다. API 키와 키 파일을 암호화해 보관하고, Codex·Claude가 키 값을 채팅에 노출하지 않고 사용할 수 있습니다.

**[Download Cellar 0.7.6 beta](https://github.com/kohana-dev/keydesk/releases/download/v0.7.6/Cellar-0.7.6-macOS-arm64.zip)** · [Latest release](https://github.com/kohana-dev/keydesk/releases/latest) · [Installation guide / 설치 안내](docs/installation.md)

Apple Silicon · macOS 14+ · Developer ID signed and Apple notarized. Intel builds are not currently provided. End users do not need an Apple Developer account.

![Cellar project vault with masked demo credentials](docs/images/cellar-vault.png)

*Actual Cellar 0.7.5 UI. Screenshots use an isolated demo vault with fictional projects and credentials; no personal vault data is shown. The current UI is in Korean.*

## What you can do

- Organize credentials by project and Development / Staging / Production environment. Add your own project images.
- Find services with inline search recommendations and recognizable provider logos.
- Store string keys and original `.p8`, `.pem`, service-account JSON, `.p12` and `.jks` files. Choose a file or drag it into the registration form.
- Deposit a new key or file while locked; it is merged into the vault and backed up after unlocking.
- Use the macOS menu bar to reopen Cellar, lock/unlock, add a key or view pending approvals.
- Copy values with 30-second clipboard cleanup; revealed values hide after 15 seconds.
- Back up the encrypted vault to iCloud Drive and store its recovery key in iCloud Keychain when available. View backup and upload status in the app.
- Use the signed CLI for SDKs, builds and original files, or MCP for supported provider API requests. View and revoke remembered approvals in the app.

![Cellar inline Gemini service search and registration](docs/images/cellar-service-search.png)

## Get started

1. Download the ZIP and `SHA256SUMS.txt` from the [release](https://github.com/kohana-dev/keydesk/releases/tag/v0.7.6), and verify the checksum.
2. Unzip and move **Cellar.app** to **`~/Applications`**. This is the installation path used by the AI connection scripts.
3. Open Cellar normally. Follow macOS authentication and check your encrypted backup / iCloud upload status.
4. In **백업·CLI 설정**, connect the bundled CLI. Add a project and register a key or original file.
5. For Codex and Claude, follow the [AI connection steps](docs/installation.md#connect-codex-and-claude). One global MCP connection routes requests using each repository's names-only project manifest.

The app bundle and executable are **Cellar.app** and **Cellar**. The compatible CLI, MCP server and skill remain named **`keydesk`**. Existing vault paths and Keychain identity are unchanged. Upgrading from `Keydesk.app`? See the [migration steps](docs/installation.md#upgrade-from-keydeskapp).

## Use credentials without putting them in chat

```sh
# Let the CLI import a key directly; do not read the env file into AI output.
keydesk store --project my-app --env dev --name OPENAI_API_KEY --from-env-file /absolute/path/.env

# Give a development tool only the selected variable.
keydesk run --project my-app --env dev --only OPENAI_API_KEY -- npm run dev

# Store an original file, then pass a private temporary file path to its tool.
keydesk store-file --project my-app --env dev --name GOOGLE_APPLICATION_CREDENTIALS --from-file /absolute/path/service-account.json
keydesk run --project my-app --env dev --files GOOGLE_APPLICATION_CREDENTIALS -- /absolute/path/to/tool
```

For direct API calls, the local broker injects authentication internally. MCP exposes `project_context` and `request_http` through the global router; there is no credential-reading tool. Supported provider requests include Gemini, OpenAI, Anthropic, Cloudflare, Paddle and RevenueCat. See [API broker](docs/local-api-broker.md), [MCP setup](docs/mcp-setup.md) and [project CLI](docs/project-cli.md).

Initial use requires human approval. Exact development commands can be remembered for 30 minutes. Production reuse is optional, lasts five minutes and allows ten additional starts/requests. Requests must match exactly; lock, key changes and quitting revoke remembered approvals. API requests in dev/staging have a separate 30-minute / 100-repeat limit.

`stored` confirms a vault save; verify backup upload separately. `queued` means encrypted on this Mac only until unlock, merge and successful backup. Source env/key files are preserved. Original files are limited to 1 MiB each; selected temporary files are cleaned up on exit, cancellation or vault lock. Intentional `--keep-running` retains injected credentials/files until the process ends.

## Build and security

SwiftUI, CryptoKit and Security; no external Swift package dependencies.

```sh
swift test
KEYDESK_SIGNING_MODE=adhoc ./scripts/build-app.sh
open dist/Cellar.app --args --demo
```

Ad-hoc builds are for demos, not real protected vaults. See [source builds and signing](docs/open-source-building.md).

Cellar is a beta, not an independently audited credential manager. Same-Mac encrypted backup recovery has been verified; restore on a separate Mac has not. Keep an independent encrypted backup and recovery key. Approved SDK/build tools receive raw credentials and can read or transmit them; output masking is not a sandbox. Deleting a local key does not revoke its provider credential or remove old backups. Read [SECURITY.md](SECURITY.md) and [verification limits](docs/open-source-readiness.md).

## Contributing and license

[Contributing](CONTRIBUTING.md) · [Security reports](SECURITY.md) · [Third-party notices](THIRD_PARTY_NOTICES.md)

Cellar code is [MIT licensed](LICENSE). Provider artwork retains its own licenses and trademarks. Never include actual credentials, private key files or vault backups in issues or pull requests.
