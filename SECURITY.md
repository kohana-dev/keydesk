# Security policy

Cellar is a local macOS secret vault. The current published app is **0.7.6**
(Apple Silicon, macOS 14+), distributed as a public beta. The CLI, MCP server,
skill names, bundle/Keychain identity and existing vault location retain
`keydesk` compatibility names. This project has not had an independent security
audit. Only the latest published release receives fixes; older releases are not
maintained separately. Updates are installed manually from the official
[GitHub releases](https://github.com/kohana-dev/keydesk/releases).
Verify the published checksum and use the signed, notarized app. Notarization
is an Apple distribution check, not an independent security audit.

## Reporting

Do not post keys, recovery codes, vaults, backups, personal screenshots or
exploit details in public issues. Use the repository's GitHub Security tab and
Report a vulnerability. Private vulnerability reporting is enabled for the
official repository (checked 2026-10-13). If private reporting is unavailable, ask for a private reporting channel
without disclosing vulnerability details.
There is no guaranteed response SLA.

## Boundaries

- Approved child programs can read and transmit injected secrets. Exact output
  masking is not protection against encoding, partial output or exfiltration.
- The signed CLI is authenticated to the app; this is not a sandbox for other
  software running as the same macOS user or for a compromised OS.
- Local vaults and backups are encrypted. Metadata inside the vault is also
  encrypted; socket requests, AI-visible names and activity UI are not anonymous.
- Recovery keys use iCloud Keychain and backups use iCloud Drive when available.
  Cellar operates no server and has no analytics. Apple services have their own
  privacy policies. Keep an independent encrypted backup and recovery key.
- Locked deposits remain only on that Mac until unlock, merge and backup upload.
- Cross-Mac iCloud Keychain sync/restore is not yet physically verified. Same-Mac
  isolated restore has been verified. Real screen lock and system sleep/wake
  transitions were exercised on the maintainer's Mac with the published app
  and a disposable demo vault; it locked and remained locked after return.
  Other macOS accounts and hardware remain unverified.
- Changing a recovery key does not invalidate old backups. Deleting a local key
  does not revoke it at its provider. Full memory erasure is not guaranteed.
- A signing identity change can make old Keychain items inaccessible. Verify a
  recovery plan before switching to a fork or separately signed build.

## Secret files (0.6.0+)

File names and original binary bytes are inside the authenticated encrypted snapshot and encrypted locked deposits. File-bearing snapshots use format 2; old readers fail closed. Restore supports both formats. Original source files are not removed. Limits: 1 MiB per file, 16 MiB serialized snapshot, 16 explicitly selected files per run.

Approved tools receive private temporary file paths (directories 700, files 600). Exit, cancellation and lock remove those files, except explicitly approved keep-running commands retain them until exit. Crash leftovers are removed on the next app launch when the owner PID no longer exists. Cleanup is best effort, and does not guarantee secure erasure on SSDs. Same-user processes are outside the isolation boundary; an approved child can read, copy or transmit secrets. Output redaction covers exact whole-file byte sequences only, not fragments or transformations. Do not use it as a data-loss prevention boundary.


## MCP, local API requests and approval reuse (0.7.x)

The repository-aware MCP exposes project names/bindings and supported JSON API
requests. It does not expose a secret-reading or file-reading tool. Cellar
injects the selected authentication value inside its trusted transport process;
the AI caller does not receive that value. Provider responses may themselves
contain sensitive account data. This is not a guarantee of comprehensive output
redaction or protection against malicious software on the Mac.

The broker permits fixed official HTTPS origins and bounded JSON requests. It
rejects redirects, arbitrary headers and private/special network destinations.
Streaming, multipart uploads, binary responses and arbitrary provider hosts are
unsupported. Original key files and SDKs use approved `keydesk run` processes;
those processes receive the selected credentials and must be trusted.

Native Cellar approval remains required for initial credential use; production
also requires macOS authentication. Opt-in exact-request reuse lasts five minutes
and up to ten additional API requests for production, or thirty minutes and up
to 100 additional requests for development/staging. CLI reuse has its own bound
command grants. Trusted local callers share grants; they are not separated by
Codex/Claude identity. Lock, key changes and app exit invalidate grants. A
permitted API call can still change or delete external data. Cancellation cannot
undo a request already accepted by a provider; check its outcome before retrying.
See [broker boundaries](docs/local-api-broker.md) for the complete contract.

## Setup and validation limits

Source-tree installers preflight selected client tools and configuration before
writing. Each command restores its own changed targets on handled failure and
keeps private backup copies of replaced files. Skill installation and MCP setup
are separate transactions. Power loss, force termination, concurrent settings
edits and filesystem failures can prevent complete rollback; do not run setup
concurrently, and heed explicit recovery instructions. No installer accesses the
vault or authenticates an AI account. Client-level MCP tool permissions do not
remove native Cellar approval or OS authentication.

Published-app signature, notarization and Gatekeeper checks, isolated setup,
configuration preservation, real system lock/sleep transitions with a demo
vault, and same-Mac isolated recovery have been exercised.
Actual Gemini calls through fresh Codex and Claude sessions have been exercised
on the maintainer's Mac. A separate Mac/new macOS user's complete first-run
Keychain flow, cross-Mac recovery, and an independent security audit remain
unverified. Tests and local demonstrations do not establish those properties.
Keep an independent recovery path; do not treat this beta as the only copy of
critical production credentials.
