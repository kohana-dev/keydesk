# Contributing

Use macOS 14+ and Swift 6.2+. Run `swift test` before proposing code changes.
Use fake credentials only; demo mode must never access a real user's vault.
See [building](docs/open-source-building.md) for signed and demo builds.
Do not weaken Keychain, peer signature checks, authentication or approval rules
just to make unsigned builds work. Explain changes to vault format, recovery,
process lifetime and authorization, and add meaningful regression coverage.
Never commit env files, personal evidence, certificates, profiles or binaries.
Public source packages are produced by `scripts/export-public-source.py`.
Brand assets keep their upstream licenses and trademark rights; new assets need
provenance and redistribution review. The repository code uses MIT.
