# AI development through MCP and the CLI

Install the signed app and bundled CLI, then run `python3 scripts/install-ai-skills.py --update` to install the Codex/Claude skills and `~/.local/bin/keydesk-project` adapter. This adapter uses Python 3 and invokes the signed CLI; it never reads secret files itself. Native unlock and execution approval remain in Keydesk.

Create `keydesk.project.json` in the repository root. It contains names and types only and may be committed:

```json
{"version":1,"project":"my-app","bindings":{"prod":{"GOOGLE_APPLICATION_CREDENTIALS":"file"},"dev":{"API_KEY":"value","SERVICE_CONFIG":"json","SERVICE_FIELDS":"keyValue"}}}
```

From the root or a child directory:

```sh
~/.local/bin/keydesk-project imports
~/.local/bin/keydesk-project describe
~/.local/bin/keydesk-project status
~/.local/bin/keydesk-project store-file --env prod --name GOOGLE_APPLICATION_CREDENTIALS --from-file /absolute/service-account.json
~/.local/bin/keydesk-project run --env prod --files GOOGLE_APPLICATION_CREDENTIALS -- python3 deploy.py
~/.local/bin/keydesk-project run --env dev --only API_KEY -- npm run dev
~/.local/bin/keydesk-project run --env dev --select 'SERVICE_TOKEN=SERVICE_CONFIG#/auth/token' --select 'REGION=SERVICE_FIELDS#/region' -- npm run dev
~/.local/bin/keydesk-project run --env dev --select 'SERVICE_TOKEN=SERVICE_CONFIG#/auth/token' --stdin-key SERVICE_TOKEN -- /absolute/path/tool login --with-token
```

The descriptor records the intended bindings, not proof they currently exist in the vault. Each run selects names explicitly; no environment or secret list is selected automatically. A file variable contains an owner-only temporary path and is removed when the process exits. Tools that use custom flags can read the variable internally and pass the path to their API client; never read file contents into an AI tool response. The working directory is preserved.

Cellar 0.7.20 adds repeatable `--select OUTPUT=SOURCE#/pointer` for key-value/JSON fields. `SOURCE` is the exact project reference; `OUTPUT` is the environment variable delivered to the approved process, or the name passed to `--stdin-key`. Combine it with `--only` API keys and `--files` original files. Every output must be unique across these selections; reserved execution-control names are rejected. The adapter checks names-only metadata, while the signed app validates the stored format, current version and selected field before approval/execution. No selected value is returned to the adapter.

Pointers follow RFC 6901: `/auth/token`, `/servers/0/token`, and `/a~1b/~0token` for field names containing `/` or `~`. The empty pointer (`OUTPUT=SOURCE#`) selects a scalar JSON root. CLI selection accepts string, number and boolean leaves, preserving number tokens; null, objects, arrays, missing fields, invalid escapes, ambiguous duplicate keys and non-document formats are rejected. Pointers are limited to 2,048 UTF-8 bytes and 64 components. Only the selected leaf is delivered, never the whole document. Obtain paths from the user or established names-only documentation; neither project metadata nor MCP lists document fields.

Manifests accept `value` (legacy API-key metadata), `apiKey`, `keyValue`, `json`, `text` and `file`. A legacy `value` entry is allowed for field selection to preserve existing project mappings, but never changes actual saved content: `--only` still accepts API keys, `--select` accepts key-value/JSON documents, and text is not injectable. `store` continues to save one API key; `store-file`/`run --files` are unchanged. App reveal/copy and document editing remain available, with Mac authentication before loading stored content for editing.

For supported direct APIs, prefer MCP `request_http` with `field` and, when needed, `provider`. The project CLI equivalent is `keydesk-project request --env dev --key SERVICE_CONFIG --field /auth/token --provider OpenAI --method GET --url https://api.openai.com/v1/models`. A document classified as Other requires explicit provider; a classified document can only use its stored provider. API authentication fields must be strings. Fixed official hosts, human approval and response filtering still apply. Field selection requires Cellar 0.7.20 and its matching CLI/adapters.

Use Cellar 0.7.19 or later and its matching bundled helper for vaults containing key-value, JSON or text content, including content kept only in version history. These vaults use format 3; older apps/helpers refuse them. Existing vaults remain readable in 0.7.19.

`keydesk status` (0.6.1+) returns `locked`, `busy`, `pendingDeposits`, `backup` and `cloudUpload`. Locked status reports backup/upload as `unknown_locked`; it does not unlock or expose project, key or filename metadata. A successful store may still be queued; merge after unlock and check backup status before removing an original.

Keydesk 0.7.0 MCP exposes `request_http` through the local API broker without delivering the selected authentication value to the AI client. Prefer MCP for supported direct APIs, and use CLI for storage, SDKs, builds and files. Metadata listing still requires its separate grant. See [MCP setup](mcp-setup.md).

Migration keeps originals until byte integrity and backup are verified. Do not change Google service-account permissions, Apple key IDs, server secrets or provider credentials as part of a local migration. If a consumer still hardcodes a source path, add support for the injected path before removing that source.

`keydesk-project imports` filters local `.config/keydesk/imported-files.json` receipts to project, environment, variable, kind and state only. This optional migration inventory is not a live vault listing. Do not record secret values in it; a deleted or renamed binding can leave a stale receipt.

Production reuse (0.6.2+) is off by default. The user may explicitly approve and authenticate an exact invocation for five minutes and ten additional starts. Direct file arguments and common package settings are hashed; child programs and imported dependencies remain outside this attestation. Expiry blocks new reuse and does not terminate a running command or revoke copied credentials at the provider. `keydesk revoke-runs` clears remembered grants; vault lock also requests termination of ordinary active runs. Risk-warning, interactive production and keep-running production commands cannot be remembered.
