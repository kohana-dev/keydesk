---
name: keydesk
description: Store and use Cellar credentials without exposing their values, including API keys, selected key-value/JSON fields and original key files. Use for authenticated API requests, credential setup, env migration and secret-dependent commands; legacy keydesk CLI/MCP names remain compatible.
---

Use Cellar (formerly Keydesk) on this Mac to keep credentials out of chat, source code, command arguments and logs. The app bundle and executable are `Cellar.app` and `Cellar`. Existing `keydesk` CLI and MCP names are intentionally retained. The signed CLI is `~/.local/bin/keydesk`; if it cannot connect, launch `~/Applications/Cellar.app`.

## Choose the connection and transport

Use the global `keydesk` MCP connection for supported direct API calls. First call `project_context` with `repository` set to this session's actual absolute repository directory. Never assume the MCP server's cwd is the repository: user-scoped Claude servers may start elsewhere. The tool reads the nearest names-only `keydesk.project.json`, or an exact matching local connection/import receipt. It does not list live vault contents. Its returned `bindings` identify API-key/document/file names and environments; these local records can be stale.

Then call the same server's `request_http` with `repository`, `environment`, `key`, `method`, `url` and optional JSON-string `body`. An optional `project` is only for a project name already established by the user; it cannot override a conflicting repository manifest. Keydesk applies its human approval to the resolved project and injects authentication internally. Keep repeated JSON body bytes identical. This is an MCP adapter using the signed CLI broker internally; the AI calls MCP, not a shell request, and never receives a credential value.

Select an environment from the current task. If only one is configured and the task does not contradict it, it is unambiguous; if several are available, clarify rather than silently choosing prod. An `unconfigured` result means the project's mapping is missing, not that another project's key should be used. Establish the intended Keydesk project and variable names from existing project metadata or user context, and save a names-only `keydesk.project.json` in this repository when authorized. Do not read .env or private key file contents to discover credentials. Project mapping does not require another MCP registration or restart. New keys can be deposited with the CLI and their names added to this manifest as part of the authorized setup.

No per-project MCP installation is needed with the global router. Its one-time setup is `python3 scripts/install-auto-mcp.py` from the Keydesk source checkout after skill installation. Existing sessions must reload/restart once after this initial setup. A legacy project-pinned server can still be used only for its explicit matching target. When the global tool is unavailable in the current session, `keydesk request` is the same broker fallback; do not call it MCP. Preserve unrelated client settings and never bypass Keydesk approval.

Use CLI `store`/`store-file` for new credentials and CLI `run --only/--files/--select` for SDKs, builds, interactive tools and original secret files; MCP does not store secrets or expose file contents. Reserve computer use for user authentication/approval and app-only operations. Successful API calls do not establish a permanent grant: prod reuse remains five minutes/ten additional exact requests and resets on lock, key changes or quit.

Prefer CLI commands over computer use. `~/.local/bin/keydesk-project imports` lists locally recorded migration receipts (project, environment, variable and kind), which can help find previously imported files. Receipts are metadata only and may be stale; actual execution is the check. If the user left project connections to its own AI session, configure that project only within the current session task. In a configured project, run `~/.local/bin/keydesk-project describe` to discover the project and variable names from `keydesk.project.json`, then `~/.local/bin/keydesk-project status` for vault readiness and backup status. The manifest contains metadata only. Select the environment and exact names explicitly, for example `~/.local/bin/keydesk-project run --env prod --files GOOGLE_APPLICATION_CREDENTIALS -- python3 deploy.py`. It invokes the signed Keydesk CLI and keeps normal human approval. Do not inspect the temporary secret file or environment through an AI read tool. UI is needed only for user authentication/approval or an app-only operation. If no manifest exists, use the raw CLI with the established project name. `keydesk status` returns no project names or values and reports backup as unknown while locked.

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

A `stored` receipt means the encrypted vault was updated; iCloud upload status must still be checked with `keydesk status` (or the app). A `queued` receipt means the locked app accepted an encrypted deposit on this Mac only. Tell the user it will be merged and backed up after the next unlock, and do not claim off-device protection before then. No unlock or execution approval is needed to queue a new key. Never overwrite a duplicate key by deleting or renaming its existing binding to evade the collision check. Preserve source env files unless removal is part of the user's requested migration; disclose that they remain.

## Use an existing key

Run the actual development tool, selecting only the variables it needs:

```sh
~/.local/bin/keydesk run --project my-app --env dev --only API_KEY -- npm run dev
```

Cellar 0.7.20 can select a known field from a **Key-value** or **JSON** item without returning the document or selected value to the AI:

```sh
~/.local/bin/keydesk run --project my-app --env dev --select 'OPENAI_API_KEY=SERVICE_CONFIG#/openai/token' --select 'REGION=SERVICE_CONFIG#/region' -- npm run dev
# The repository adapter supports the same selectors and can combine --only/--files.
~/.local/bin/keydesk-project run --env dev --select 'API_TOKEN=SERVICE_CONFIG#/token' --stdin-key API_TOKEN -- /absolute/path/tool login --with-token
```

`OUTPUT=SOURCE#/pointer` maps the selected scalar to a named environment output; `SOURCE` is an already established project reference. The pointer follows RFC 6901: `/servers/0/token` selects an array element, `~1` escapes `/` and `~0` escapes `~` inside a field name. The empty pointer (`OUTPUT=SOURCE#`) selects a JSON scalar root. CLI fields accept strings, JSON number tokens and booleans; null, arrays and objects are rejected. Text/file/API-key items are not document selectors. Output collisions across `--only`, `--files` and `--select`, reserved execution-control names, invalid/missing fields and ambiguous duplicate JSON keys fail closed. `--stdin-key` can name a selected field output instead of an API-key output. Only selected values reach the approved process; whole documents are never implicitly delivered.

Obtain field paths from the user or existing names-only project documentation. Neither MCP metadata nor a manifest enumerates document fields, and there is no field-reading/export tool. Do not reveal/copy a document, read a private source file or print an injected value merely to discover a path. In `keydesk.project.json`, use `keyValue` or `json` for document bindings (`apiKey`, `text`, `file` and legacy `value` are also understood). Legacy `value` metadata can point to a document; the signed app validates its actual current format at execution.

For a CLI that accepts a token on stdin, use `--stdin-key API_KEY` with the tool's documented stdin login command. For a real interactive terminal use `--interactive`; it cannot be combined with `--stdin-key`.

By default, the user unlocks the vault and approves the first run. An exact development invocation can be remembered for 30 minutes. Production defaults to approval and OS authentication each time. The user may explicitly select an exact-command grant lasting five minutes and at most ten additional starts; repeated use neither extends expiry nor refreshes its budget. Never select this option for the user. Risk-warning, interactive production and keep-running production invocations cannot be remembered. Direct file arguments and common package configuration are fingerprinted, but dependencies and child tools are not fully attested. Grant expiry stops new reuse, not a process already running. `keydesk revoke-runs` clears remembered approvals without ending existing processes. Locking the vault, changing keys or quitting the app also clears remembered approvals. If approval expires or is rejected, stop that attempt and ask the user to indicate readiness before retrying. Do not auto-click approval or OS authentication.

The user can separately authenticate and start a 1–480 minute **Allow all requests temporarily** session in app Settings or the menu bar. While active, individual CLI/API/MCP approvals are automatic, including production; selection validation and official-host limits still apply. The CLI/MCP cannot activate or extend it. This setting does not expand the AI's task authorization. Stop/expiry/lock/quit returns to individual approval; never enable the session or change its duration for the user.

Do not print, encode, inspect process environments, expose or send keys just to check they exist. Verify tool success or a boolean presence check. Output masking covers exact raw values, not arbitrary transformations; approved tools can read and transmit the injected secret. `--keep-running` retains a process and its already-injected secrets after vault lock; use it only when that persistent development behavior is intended.

## Call an API without receiving its authentication value

Keydesk 0.7.0 adds a local HTTP broker. Check `keydesk --help` for `request` before using it on an older installation. For direct HTTP work prefer this path over giving a token to curl or an AI-authored script:

```sh
~/.local/bin/keydesk request --project my-app --env dev --key CLOUDFLARE_API_TOKEN --method GET --url https://api.cloudflare.com/client/v4/user/tokens/verify
```

For an already known string field in a Key-value or JSON document:

```sh
~/.local/bin/keydesk request --project my-app --env dev --key SERVICE_CONFIG --field /openai/token --provider OpenAI --method GET --url https://api.openai.com/v1/models
```

The global MCP `request_http` accepts the same `field` (RFC 6901 pointer, including empty root) and optional `provider`. If the document's service is **Other**, an explicit supported `provider` is required. For a document classified as a supported service, omit `provider` or supply the identical provider; this cannot redirect a credential to another service. The selected API value must be a nonempty valid string: numbers/booleans that are usable for CLI configuration are not API authentication tokens. The broker retains its fixed official hosts and never returns the selected value. Provider, pointer and current item version participate in approval matching; changing the selected field requires new approval unless the user has separately enabled a temporary all-request session.

In a configured project, `keydesk-project request --env dev --key NAME --method GET --url URL` selects an existing API-key binding; add `--field /path --provider OpenAI` to select a document field. For a JSON write request use `--body-file /absolute/path/request.json`. Keep authentication values out of that file. The broker supports OpenAI, Anthropic, Gemini, GitHub, Cloudflare, Paddle, RevenueCat, Stripe, Resend, Vercel and Sentry on their fixed official API hosts. Cellar 0.7.21 also supports OpenWeather, WeatherAPI, Tomorrow.io, Visual Crossing, Weatherbit and AccuWeather. It rejects custom/private endpoints, redirects and arbitrary headers. Apple .p8, Google service-account files, SDK/build/deploy tools and unsupported providers continue to use `keydesk run --files/--only`; do not convert stored file contents into a token yourself.

Weather providers accept **GET without a body**. Use only their exact official hosts: `api.openweathermap.org`, `api.weatherapi.com`, `api.tomorrow.io`, `weather.visualcrossing.com`, `api.weatherbit.io` and `dataservice.accuweather.com`, respectively. Supply non-secret location/options only; never copy auth parameters or key placeholders from provider documentation. OpenWeather uses an internally inserted `appid` query; WeatherAPI, Visual Crossing and Weatherbit use an internally inserted `key` query. Tomorrow.io uses an `apikey` header; AccuWeather uses Bearer authentication. User-supplied weather auth query parameters are rejected, including encoded/case variants. For example:

```sh
~/.local/bin/keydesk request --project my-app --env dev --key WEATHER_CONFIG --field /weather/token --provider OpenWeather --method GET --url 'https://api.openweathermap.org/data/2.5/weather?lat=37.5665&lon=126.9780&units=metric'
```

MCP uses the identical non-secret URL, `key`, `field` and `provider`. The app inserts the selected credential internally; no auth value belongs in the MCP body, shell arguments or user-facing URL. These providers require Cellar 0.7.21 and matching adapters; reload existing MCP sessions after updating. Do not create provider accounts or change plans merely because a provider is now supported.

The user must approve the initial request. If they choose reuse, the exact project, environment, key version, method, URL including query and JSON body can repeat for five minutes/ten additional requests in prod, or thirty minutes/100 additional requests in dev/staging. Changed requests need fresh approval. Do not select reuse or click approval on the user's behalf. Expiry/rejection ends the attempt; wait for the user before retrying. AI cannot widen these policies. Approval status and per-grant revocation are in the app's AI connection screen.

Stdout is JSON containing `requestId`, HTTP `status`, response `body`, `approval` (`new` or `reused`) and `credentialDelivery`. HTTP 4xx/5xx returns exit code 2; transport/approval failures return 1. Fake-key 401 responses prove routing, not valid provider authentication. No automatic retry occurs; a timeout/cancellation may have an unknown external outcome. Verify writes before retrying. The broker blocks common reflections of the selected token, but API responses may still contain sensitive account data. Do not request credential-export endpoints or forward sensitive results to unrelated services.

MCP exposes `request_http` with `key`, `method`, `url`, optional JSON-string `body`, and optional document `field`/`provider`, using the same broker and human approval as CLI. The native pinned-project server fixes project/environment in its configuration; the global repository-aware adapter resolves them from the explicit repository and environment on each request. Metadata tools still require their separate name-listing grant. Neither path provides a key-reading tool. Run commands receive raw values/files and retain the limitations described above.

## Store and use an original secret file

For an existing .p8, .pem, service-account JSON, .p12 or .jks file, pass its path to the CLI; do not read, cat, parse or base64 its contents into model/tool output:

```sh
~/.local/bin/keydesk store-file --project my-app --env dev --name GOOGLE_APPLICATION_CREDENTIALS --from-file /absolute/path/service-account.json
~/.local/bin/keydesk run --project my-app --env dev --files GOOGLE_APPLICATION_CREDENTIALS -- /absolute/path/to/development-tool
```

`--files` accepts comma-separated variable names and can be combined with `--only` for string keys. Each selected variable contains a temporary **file path**, not the file contents. Configure the target tool to read that path using its documented file option or environment variable. Only explicit file selections are delivered. Files are limited to 1 MiB each; directories and symbolic links are rejected. Empty files and arbitrary binary bytes are supported. Original filename and bytes, including trailing newlines, are preserved. Preserve the source file unless the user authorized its removal.

The locked `queued` workflow and user approval rules above apply to files too. The temporary directory is mode 700 and files mode 600; normal exit, cancellation and vault lock remove them. With intentionally selected `--keep-running`, files remain until that command ends. A crashed app may leave temporary files until its next launch; deletion does not guarantee physical erasure from SSDs. Same-user malware and an approved tool can read, copy or transmit the files. Exact whole-file output masking is not a sandbox and does not mask transformed or partial contents. Do not inspect or print the temporary file to verify success; verify the target tool's result.

File-bearing vaults use format 2 and require Keydesk 0.6.0 or later. Older apps reject them; never downgrade a file-bearing vault.

Cellar key-value, JSON and text documents (including historical versions) use vault format 3 and require Cellar 0.7.19 or later. Field selection requires 0.7.20 and its matching bundled CLI; update the installed app and these adapters together, then reload existing MCP sessions to load the new tool schema. The installer refreshes canonical `keydesk` skills and existing `cellar` aliases while keeping their invocation names.
