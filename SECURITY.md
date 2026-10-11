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
