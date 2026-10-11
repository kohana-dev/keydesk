---
name: keydesk
description: Store newly created or received API keys and development secrets in the local Keydesk vault, and run tools with existing keys without printing their values. Use when configuring API credentials, receiving provider tokens, migrating an env file, or launching a command that needs a secret.
---

Use Keydesk on this Mac to keep credentials out of chat, source code, command arguments and logs. The signed CLI is `~/.local/bin/keydesk`; if it cannot connect, launch `~/Applications/Keydesk.app`.

Choose the project's existing name and the correct `dev`, `staging` or `prod` environment. If neither session context nor project configuration establishes the target, ask for the project/environment; do not guess for production. Keydesk accepts a new project name on first store.

## Store a new key

When creating a provider credential as part of an authorized task, route its value directly into Keydesk. Do not first return the provider response or value to the model. A task to configure credentials authorizes storing the resulting key in the matching project; it does not authorize creating extra provider accounts or changing permissions.

For a key already in a local env file, let the CLI read it internally:

```sh
~/.local/bin/keydesk store --project my-app --env dev --name API_KEY --from-env-file /absolute/path/to/.env
```

Do not read, cat or grep the env file's values into tool output. For a provider command or local script that produces a key on stdout, pipe that output directly into:

```sh
~/.local/bin/keydesk store --project my-app --env dev --name API_KEY --stdin
```

Never put the key in an `echo`, command argument, shell tracing output or temporary plaintext file. If the key is only visible in a user interface, ask the user to paste it into Keydesk's secure input, rather than requesting it in chat or using screen capture on the value.

A `stored` receipt means the encrypted vault was updated; iCloud upload status must still be checked in the app. A `queued` receipt means the locked app accepted an encrypted deposit on this Mac only. Tell the user it will be merged and backed up after the next unlock, and do not claim off-device protection before then. No unlock or execution approval is needed to queue a new key. Never overwrite a duplicate key by deleting or renaming its existing binding to evade the collision check. Preserve source env files unless removal is part of the user's requested migration; disclose that they remain.

## Use an existing key

Run the actual development tool, selecting only the variables it needs:

```sh
~/.local/bin/keydesk run --project my-app --env dev --only API_KEY -- npm run dev
```

For a CLI that accepts a token on stdin, use `--stdin-key API_KEY` with the tool's documented stdin login command. For a real interactive terminal use `--interactive`; it cannot be combined with `--stdin-key`.

The user unlocks the vault and approves the first run. An exact development invocation can be remembered for 30 minutes. Production and commands with risk warnings require approval each time. Locking the vault, changing keys or quitting the app clears remembered approvals. If approval expires or is rejected, stop that attempt and ask the user to indicate readiness before retrying. Do not auto-click approval or OS authentication.

Do not print, encode, inspect process environments, expose or send keys just to check they exist. Verify tool success or a boolean presence check. Output masking covers exact raw values, not arbitrary transformations; approved tools can read and transmit the injected secret. `--keep-running` retains a process and its already-injected secrets after vault lock; use it only when that persistent development behavior is intended.

Keydesk MCP is metadata-only. It can list authorized variable/provider names, not secret values or provider API responses. Use `keydesk run` for actual work.
