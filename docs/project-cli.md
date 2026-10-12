# AI development through MCP and the CLI

Install the signed app and bundled CLI, then run `python3 scripts/install-ai-skills.py --update` to install the Codex/Claude skills and `~/.local/bin/keydesk-project` adapter. This adapter uses Python 3 and invokes the signed CLI; it never reads secret files itself. Native unlock and execution approval remain in Keydesk.

Create `keydesk.project.json` in the repository root. It contains names and types only and may be committed:

```json
{"version":1,"project":"my-app","bindings":{"prod":{"GOOGLE_APPLICATION_CREDENTIALS":"file"},"dev":{"API_KEY":"value"}}}
```

From the root or a child directory:

```sh
~/.local/bin/keydesk-project imports
~/.local/bin/keydesk-project describe
~/.local/bin/keydesk-project status
~/.local/bin/keydesk-project store-file --env prod --name GOOGLE_APPLICATION_CREDENTIALS --from-file /absolute/service-account.json
~/.local/bin/keydesk-project run --env prod --files GOOGLE_APPLICATION_CREDENTIALS -- python3 deploy.py
~/.local/bin/keydesk-project run --env dev --only API_KEY -- npm run dev
```

The descriptor records the intended bindings, not proof they currently exist in the vault. Each run selects names explicitly; no environment or secret list is selected automatically. A file variable contains an owner-only temporary path and is removed when the process exits. Tools that use custom flags can read the variable internally and pass the path to their API client; never read file contents into an AI tool response. The working directory is preserved.

`keydesk status` (0.6.1+) returns `locked`, `busy`, `pendingDeposits`, `backup` and `cloudUpload`. Locked status reports backup/upload as `unknown_locked`; it does not unlock or expose project, key or filename metadata. A successful store may still be queued; merge after unlock and check backup status before removing an original.

Keydesk 0.7.0 MCP exposes `request_http` through the local API broker without delivering the selected authentication value to the AI client. Prefer MCP for supported direct APIs, and use CLI for storage, SDKs, builds and files. Metadata listing still requires its separate grant. See [MCP setup](mcp-setup.md).

Migration keeps originals until byte integrity and backup are verified. Do not change Google service-account permissions, Apple key IDs, server secrets or provider credentials as part of a local migration. If a consumer still hardcodes a source path, add support for the injected path before removing that source.

`keydesk-project imports` filters local `.config/keydesk/imported-files.json` receipts to project, environment, variable, kind and state only. This optional migration inventory is not a live vault listing. Do not record secret values in it; a deleted or renamed binding can leave a stale receipt.

Production reuse (0.6.2+) is off by default. The user may explicitly approve and authenticate an exact invocation for five minutes and ten additional starts. Direct file arguments and common package settings are hashed; child programs and imported dependencies remain outside this attestation. Expiry blocks new reuse and does not terminate a running command or revoke copied credentials at the provider. `keydesk revoke-runs` clears remembered grants; vault lock also requests termination of ordinary active runs. Risk-warning, interactive production and keep-running production commands cannot be remembered.
