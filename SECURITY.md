# Security policy

Keydesk is a local macOS secret vault. This project has not had an independent
security audit. Current development targets the 0.5.x line; older versions are
not maintained separately. Updates are installed manually.

## Reporting

Do not post keys, recovery codes, vaults, backups, personal screenshots or
exploit details in public issues. Use the repository's GitHub Security tab and
Report a vulnerability when private reporting is enabled. Before enabling a
public release, the maintainer must enable private vulnerability reporting.
If unavailable, ask for a private reporting channel without disclosing details.
There is no guaranteed response SLA.

## Boundaries

- Approved child programs can read and transmit injected secrets. Exact output
  masking is not protection against encoding, partial output or exfiltration.
- The signed CLI is authenticated to the app; this is not a sandbox for other
  software running as the same macOS user or for a compromised OS.
- Local vaults and backups are encrypted. Metadata inside the vault is also
  encrypted; socket requests, AI-visible names and activity UI are not anonymous.
- Recovery keys use iCloud Keychain and backups use iCloud Drive when available.
  Keydesk operates no server and has no analytics. Apple services have their own
  privacy policies. Keep an independent encrypted backup and recovery key.
- Locked deposits remain only on that Mac until unlock, merge and backup upload.
- Cross-Mac iCloud Keychain sync/restore is not yet physically verified. Same-Mac
  isolated restore has been verified. Physical sleep/screen lock remains a
  separate manual check; automated state tests do not prove it.
- Changing a recovery key does not invalidate old backups. Deleting a local key
  does not revoke it at its provider. Full memory erasure is not guaranteed.
- A signing identity change can make old Keychain items inaccessible. Verify a
  recovery plan before switching to a fork or separately signed build.

## Secret files (0.6.0+)

File names and original binary bytes are inside the authenticated encrypted snapshot and encrypted locked deposits. File-bearing snapshots use format 2; old readers fail closed. Restore supports both formats. Original source files are not removed. Limits: 1 MiB per file, 16 MiB serialized snapshot, 16 explicitly selected files per run.

Approved tools receive private temporary file paths (directories 700, files 600). Exit, cancellation and lock remove those files, except explicitly approved keep-running commands retain them until exit. Crash leftovers are removed on the next app launch when the owner PID no longer exists. Cleanup is best effort, and does not guarantee secure erasure on SSDs. Same-user processes are outside the isolation boundary; an approved child can read, copy or transmit secrets. Output redaction covers exact whole-file byte sequences only, not fragments or transformations. Do not use it as a data-loss prevention boundary.
