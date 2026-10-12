# One MCP connection for all local projects

Install the signed app/CLI, both AI clients and Python 3.11 or later. Install the personal skills and repository-aware MCP adapter, then register the one global connection:

```sh
python3 scripts/install-ai-skills.py --update
python3 scripts/install-auto-mcp.py
```

Restart/reload Codex and Claude Code once. Both now have a user-level server named `keydesk`, exposing `project_context` and `request_http`. No project or production environment is chosen as a global default. Future project mappings do not require another MCP registration or session restart.

Each repository should contain names-only metadata:

```json
{"version":1,"project":"my-app","bindings":{"dev":{"GEMINI_API_KEY":"value"},"prod":{"GOOGLE_APPLICATION_CREDENTIALS":"file"}}}
```

The skill calls `project_context(repository: ABSOLUTE_REPOSITORY_PATH)`, which reads the nearest `keydesk.project.json`. If absent, it can use an exact repository-name match from the local connection/import metadata. These receipts can be stale. An explicit established `project` name can select matching local registry metadata, but cannot override a conflicting repository manifest. No fuzzy match, provider-wide key fallback or global default production key is used.

When the target/environment is clear, the session calls `request_http` with `repository`, `environment`, `key`, `method`, `url` and optional JSON-string `body`. The adapter validates this binding and invokes the signed `keydesk request` CLI internally. Keydesk resolves the actual stored key, inserts authentication and enforces its existing user approval. This is a local MCP adapter over the signed CLI broker, not the original project-pinned native MCP implementation. No credential value is returned to the adapter or the AI.

An unmapped repository needs a one-time project mapping, not a per-project MCP installation. Its AI session can add `keydesk.project.json` as part of authorized credential setup once the intended project/name bindings are established. Several plausible environments require clarification; a provider being available does not authorize borrowing another project's production key. Explicit session repository paths are required because user-scoped Claude servers can start outside the repository.

Only these two MCP tools are preauthorized at the AI-client layer. Keydesk's human first-request approval, OS authentication and exact-request reuse limits remain unchanged. There is no automatic production grant. Cancellation/disconnection stops the adapter's helper; an API request already submitted can have an unknown external outcome, so it is never automatically retried. Client-managed denial policies still apply.

Storage and original files continue through `keydesk store`, `store-file` and `run --only/--files`; the MCP adapter does not read private key files or implement secret export. There is no public listener, system proxy, system CA or cloud server. Cloud/remote clients cannot use the Mac's private local socket just by installing these settings.

The previous `install-mcp.py` and `keydesk-connect` remain available for explicitly project-pinned native MCP setups. Prefer the single router for normal multi-project development.

References: [Codex MCP configuration](https://developers.openai.com/codex/mcp), [Claude MCP user scope](https://code.claude.com/docs/en/mcp#user-scope).

## Upgrade from Keydesk.app to Cellar.app

Version 0.7.5 names the app bundle `Cellar.app` and its executable `Cellar`. The `keydesk` helper, MCP server names, vault data and Keychain identity stay unchanged. Quit the old app, install Cellar.app in `~/Applications`, then run `python3 scripts/migrate-cellar-paths.py` and `python3 scripts/install-ai-skills.py --update`. The migration backs up user client settings and only replaces exact legacy helper paths; global repository-aware MCP settings remain intact. For a project-local MCP config, add `--config /path/to/.mcp.json`. Reload existing AI sessions if they cached a directly pinned legacy app path.
