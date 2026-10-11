# AI development through the CLI

Install the signed app and bundled CLI, then run `python3 scripts/install-ai-skills.py --update` to install the Codex/Claude skills and `~/.local/bin/keydesk-project` adapter. This adapter uses Python 3 and invokes the signed CLI; it never reads secret files itself. Native unlock and execution approval remain in Keydesk.

Create `keydesk.project.json` in the repository root. It contains names and types only and may be committed:

```json
{"version":1,"project":"my-app","bindings":{"prod":{"GOOGLE_APPLICATION_CREDENTIALS":"file"},"dev":{"API_KEY":"value"}}}
```

From the root or a child directory:

```sh
~/.local/bin/keydesk-project describe
~/.local/bin/keydesk-project status
~/.local/bin/keydesk-project store-file --env prod --name GOOGLE_APPLICATION_CREDENTIALS --from-file /absolute/service-account.json
~/.local/bin/keydesk-project run --env prod --files GOOGLE_APPLICATION_CREDENTIALS -- python3 deploy.py
~/.local/bin/keydesk-project run --env dev --only API_KEY -- npm run dev
```

The descriptor records the intended bindings, not proof they currently exist in the vault. Each run selects names explicitly; no environment or secret list is selected automatically. A file variable contains an owner-only temporary path and is removed when the process exits. Tools that use custom flags can read the variable internally and pass the path to their API client; never read file contents into an AI tool response. The working directory is preserved.

`keydesk status` (0.6.1+) returns `locked`, `busy`, `pendingDeposits`, `backup` and `cloudUpload`. Locked status reports backup/upload as `unknown_locked`; it does not unlock or expose project, key or filename metadata. A successful store may still be queued; merge after unlock and check backup status before removing an original.

The existing MCP endpoint remains metadata-only and requires its scoped metadata grant. A public HTTP service or get-secret MCP endpoint is unnecessary for local development. Use these CLI commands for storage and process execution, and reserve UI interaction for user authentication/approval and UI-specific operations.

Migration keeps originals until byte integrity and backup are verified. Do not change Google service-account permissions, Apple key IDs, server secrets or provider credentials as part of a local migration. If a consumer still hardcodes a source path, add support for the injected path before removing that source.
