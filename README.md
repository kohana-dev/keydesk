# Keydesk

A local macOS secret vault for individual developers. Store API keys by project
and dev/staging/prod environment; let approved tools use them through a signed
CLI without putting values into AI chat. SwiftUI, CryptoKit and Security;
no external Swift package dependencies. Current version: 0.6.1 beta.

개인 개발자를 위한 macOS 로컬 API 키 금고입니다. 실제 개인 사용과
Codex·Claude 별도 세션은 검증했습니다. 공개 배포는 베타이며,
다른 Mac 복원과 독립 보안 감사는 아직 완료하지 않았습니다.

## Features

- AES-256-GCM encrypted vault and backups, OS authentication, automatic lock.
- iCloud Drive backup and iCloud Keychain recovery key when available;
  same-Mac isolated recovery verification with `keydesk verify-recovery`.
- Project environments, search, favorites, notes, versioned key replacement.
- Clipboard copy with 30-second cleanup; reveal expires after 15 seconds.
- Locked encrypted deposit, merged/backed up after the next unlock.
- Automatic service classification from clear variable names, brand logos,
  categorized inline service recommendations; ambiguous API_KEY stays Other.
- `keydesk run`, stdin tokens and interactive CLI support.
- Codex and Claude companion skill; optional metadata-only MCP.

## Install / build

Download the signed, notarized [Keydesk 0.6.1 beta for Apple Silicon](https://github.com/kohana-dev/keydesk/releases/download/v0.6.1/Keydesk-0.6.1-macOS-arm64.zip).
Requires macOS 14 or later on an Apple Silicon Mac. Intel builds are not provided.
Unzip, move Keydesk.app to Applications (or ~/Applications), and open it normally.
No Apple Developer account is needed. Authenticate through macOS when prompted;
then enable the bundled CLI in Backup / CLI settings. iCloud Drive and iCloud
Keychain must be enabled for automatic cloud backup and recovery. If not available,
choose a backup location and keep your recovery key separately. Check the upload
status after saving. Verify SHA256SUMS.txt from the release before installing.
Do not use a demo build as a real vault or bypass Gatekeeper warnings.

다운로드한 ZIP을 풀고 Keydesk.app을 응용 프로그램 폴더로 옮겨 실행하세요.
최초 실행 안내에 따라 OS 인증·백업 상태를 확인하고, 설정에서 CLI를 연결합니다.
Apple Silicon Mac / macOS 14 이상을 지원하는 베타 버전입니다.

For source build requirements, signing and packaging see
[building](docs/open-source-building.md) and [readiness](docs/open-source-readiness.md).

```sh
swift test
KEYDESK_SIGNING_MODE=adhoc ./scripts/build-app.sh
open dist/Keydesk.app --args --demo
```

## CLI and AI workflows

In the app, connect the bundled CLI from Backup / CLI settings. Use only the
variables required by a command:

```sh
keydesk store --project my-app --env dev --name OPENAI_API_KEY --from-env-file /absolute/path/.env
keydesk run --project my-app --env dev --only OPENAI_API_KEY -- npm run dev
keydesk run --project my-app --env dev --stdin-key GITHUB_TOKEN -- gh auth login --with-token
keydesk run --project my-app --env dev --only API_KEY --interactive -- tool-login
```

Do not pass values as arguments or print env files. `stored` means saved in the
vault; check upload status separately. `queued` means encrypted on this Mac
only until the next unlock and successful backup. Duplicates are not overwritten.
Install the companion skill with `python3 scripts/install-ai-skills.py`.
Explicit invocation: Codex `$keydesk`, Claude `/keydesk`. Automatic skill
selection depends on the model. MCP provides names, never secret values.

First execution requires user approval. An exact safe development invocation
can be remembered for 30 minutes. Locking, editing keys and quitting clear it.
Production and risky commands require approval every time. Default auto-lock
is 30 minutes; screen lock and sleep also trigger locking. Approved tools can
read and transmit injected keys. Output masking covers exact values only.
`--keep-running` intentionally allows an approved process to retain its keys
past vault lock; use only when needed.

## Recovery and security

Keep an independent encrypted backup and recovery key in addition to iCloud.
Other-Mac iCloud restore is not physically verified. Deleting a key does not
revoke provider credentials or remove old backups. Changing signing identity
may require recovery. Read [SECURITY.md](SECURITY.md) before storing critical keys.
Do not submit actual keys or backups in issues. See
[CONTRIBUTING.md](CONTRIBUTING.md) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

Keydesk code: [MIT](LICENSE). Third-party artwork keeps its own licenses and
trademarks; unreviewed website icons are omitted from public source exports.

### Original secret files

Choose **파일 원본 보관** in the app, then select or drop a file. Keydesk encrypts its original filename and bytes without text conversion. Locked deposits also accept files.

```sh
keydesk store-file --project my-app --env dev --name GOOGLE_APPLICATION_CREDENTIALS --from-file /absolute/path/service-account.json
keydesk run --project my-app --env dev --files GOOGLE_APPLICATION_CREDENTIALS -- /absolute/path/to/tool
```

Selected variables hold private temporary file paths. Files are removed on command exit, cancellation and vault lock; intentional `--keep-running` preserves them until exit. Files are limited to 1 MiB each (the encrypted snapshot limit remains 16 MiB). Only regular files are accepted. Source files are preserved. File-bearing vaults require 0.6.0+, use format 2, and cannot be opened by earlier versions. This also applies to their backups.

AI companion skills instruct Codex and Claude to pass source paths directly to the CLI without reading their contents. Update installed skills with `python3 scripts/install-ai-skills.py --update`; previous skills are backed up.

For CLI-first AI development, use the [project CLI adapter and readiness status](docs/project-cli.md). Project manifests contain variable names and types only; execution still uses the signed CLI and native approval.
