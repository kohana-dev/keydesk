# Local API broker (0.7.0)

Use `keydesk request` for direct JSON HTTP calls without delivering authentication values to the AI's calling process. Existing `run`, `--only`, `--stdin-key`, `--interactive` and `--files` remain available for SDKs and development tools.

```sh
keydesk request --project my-app --env dev --key CLOUDFLARE_API_TOKEN --method GET --url https://api.cloudflare.com/client/v4/user/tokens/verify
keydesk request --project my-app --env prod --key PADDLE_API_KEY --method POST --url https://api.paddle.com/customers --body-file request.json
```

The second example creates an external resource and requires task authorization and human approval. Authentication values must not appear in the URL, JSON body, command arguments or chat. The referenced key must be a value key, correctly classified in the vault. File keys are not converted into JWTs: Apple .p8 and service-account files continue to use `run --files`.

Supported fixed origins:

| Provider | Host | Authentication |
| --- | --- | --- |
| OpenAI | api.openai.com | Bearer |
| Gemini | generativelanguage.googleapis.com | x-goog-api-key |
| Anthropic | api.anthropic.com | x-api-key; version 2023-06-01 |
| GitHub | api.github.com | Bearer; API version 2022-11-28 |
| Cloudflare | api.cloudflare.com | Bearer API token (not global key/email) |
| Paddle | api.paddle.com, sandbox-api.paddle.com | Bearer |
| RevenueCat | api.revenuecat.com | Bearer |
| Stripe | api.stripe.com | Bearer |
| Resend | api.resend.com | Bearer |
| Vercel | api.vercel.com | Bearer |
| Sentry | sentry.io | Bearer; custom self-hosted origins unsupported |

The request uses the same signed local CLI and private Unix socket as existing commands. No listening TCP port, new account or remote Keydesk server is added. Provider secrets remain in the vault. The app invokes the macOS system TLS client, `/usr/bin/curl`; the selected authentication value goes to its stdin configuration, never its command arguments, environment or a temporary file. This trusted app-managed subprocess receives the value. This is not a guarantee against malware running as the same user.

## Human permission and repeat use

Cellar 0.7.14 also supports **Settings → Allow all requests temporarily**. A user unlocks the vault, chooses 1–480 minutes and authenticates once to start. During that session, CLI, supported API and MCP approvals for every project and environment, including production, are automatic. The setting cannot be activated or extended through CLI/MCP. Stop, expiry, vault lock or quitting clears the session and remembered permissions; stopping or expiry lets already accepted work continue. Vault lock and quitting retain their existing process-cancellation behavior. Request validation, project/key matching, official-host restrictions and credential delivery rules remain enforced.

By default, the initial request requires approval in the app; production additionally requires OS authentication. Reuse is opt-in, initially unchecked. A remembered grant binds the project UUID, environment, key ID/version, HTTP method, exact URL including query and exact JSON string. Project name and UUID aliases resolve to the same project before matching. These grants are shared by trusted local CLI/MCP callers, not isolated by AI identity; the approval UI explicitly says so.

- Production: 300 seconds and at most ten additional requests.
- Development/staging: 1,800 seconds and at most 100 additional requests.
- Successful reuse does not extend expiry or refill the budget.
- Reservation occurs on the app's main actor before execution, so concurrent calls cannot exceed the budget.
- Changing the request, keys or vault state, expiry and exhaustion require a fresh approval.
- Locking, changing keys and quitting revoke the grants; they are memory-only and never restored from a backup.
- The AI connection screen displays CLI, API and metadata permissions separately, with remaining time/use counts and per-grant revocation. It also exposes separate running-command termination and API cancellation controls.

Revoking a grant blocks future starts; it does not automatically cancel an in-flight operation. Cancelling or locking requests cancellation of API transport. A write may already have reached the provider, so an interrupted operation has an unknown outcome and must be checked before retrying. The transport never automatically retries any request.

## Transport and results

Only HTTPS/443 and fixed official hosts are accepted. User-info and fragments are rejected. DNS resolves IPv4, rejects private/special destinations, and the selected public IPv4 is pinned with curl `--resolve`. TLS still validates the original host and uses its SNI. IPv6-only destinations are unsupported. Redirects, proxies, curl user configuration, arbitrary caller headers and automatic retries are disabled. The network transfer has a 10-second connection and 30-second overall timeout after DNS resolution. Four API requests may be in flight.

JSON request bodies are limited to 256 KiB. Buffered UTF-8 response bodies are limited to 1 MiB; streaming, multipart uploads, binary downloads and custom headers are not supported in this version. Response headers are not returned. HEAD returns an empty body. Common raw/base64/hex/percent-encoded/JSON-escaped reflections of the selected authentication value fail closed. This is a defensive filter, not a proof that every transformation or sensitive account field is removed. A permitted API can return sensitive data or perform destructive operations even when the key itself stays hidden.

Stdout contains JSON:

```json
{"requestId":"...","status":401,"body":"...","approval":"new","credentialDelivery":"broker_only"}
```

The `approval` field is `new` for an individual approval, `reused` for a remembered request, or `timed` when the user’s temporary allow-all session admits the request.

HTTP 4xx/5xx: exit code 2. Successful 2xx: exit code 0. Approval, transport, redirect, size, reflection or cancellation failure: exit code 1 with a generic error. No request body, authentication header, raw upstream error or secret is put in activity records. The encrypted activity log correlates starts/results with a request ID and approval reuse. It is not tamper-proof audit evidence.

MCP `request_http` accepts `key`, `method`, `url`, optional JSON-string `body` and uses the identical approval and transport path. Project/environment are pinned by the MCP server configuration. Metadata tools retain their separate name-listing permission. Untrusted provider results must be treated as data, not instructions.

## Verification boundaries

Unit tests cover target checks, bounded JSON parsing, exact request/version binding, expiry/budget, individual revocation, lock and mutation invalidation, production OS authentication, reuse without reauthentication and common token reflection rejection. Existing CLI/file/PTY tests continue to run. Real Codex/Claude smoke tests use disposable fake keys: provider authentication errors prove transport and client integration, not valid authenticated provider operations. No claim of independent security audit, complete DLP or process sandboxing is made.

Authentication references: [Gemini](https://ai.google.dev/gemini-api/docs/api-key), [Cloudflare](https://developers.cloudflare.com/api/resources/user/subresources/tokens/methods/verify/), [Paddle](https://developer.paddle.com/api-reference/about/authentication/), [RevenueCat](https://www.revenuecat.com/docs/api-v2).
