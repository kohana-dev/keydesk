# Install Cellar / Cellar 설치 안내

The official app is **Cellar.app**, with a **Cellar** executable. The `keydesk` CLI, MCP server and companion skill names stay compatible with earlier installations.

## Requirements

- Apple Silicon Mac with macOS 14 or later. The current release does not include Intel binaries.
- No Apple Developer membership is required to install the official signed, notarized app.
- For automatic cloud backup/recovery: the same Apple account, iCloud Drive and iCloud Keychain enabled. Check upload status; choosing an iCloud folder alone does not prove the file has uploaded.
- For AI setup: Git, Python 3.11+, the selected AI CLI(s) installed (both for the default recipe). Sign in to each selected AI client before asking it to work. The app itself does not require Git or Python.
- Official setup references: [Python for macOS](https://www.python.org/downloads/macos/), [Git for macOS](https://git-scm.com/downloads/mac), [Codex CLI](https://developers.openai.com/codex/cli/) and [Claude Code setup](https://code.claude.com/docs/en/setup).

## Download and install

1. Open the [latest release](https://github.com/kohana-dev/keydesk/releases/latest). Download its `Cellar-<version>-macOS-arm64.zip` and `SHA256SUMS.txt` into the same folder.
2. Verify the checksum in that download folder:

   ```sh
   shasum -a 256 -c SHA256SUMS.txt
   ```

   Continue only when the ZIP reports `OK`.
3. Unzip and move **Cellar.app** into your user Applications folder, **`~/Applications`**. In Finder, choose **Go → Go to Folder** and enter `~/Applications`; create the folder if needed. The AI installers currently expect this location. `/Applications` can run the app, but is not the path used by these setup scripts.
4. Open Cellar normally. Follow its first-run flow and authenticate in the macOS prompt. Do not bypass Gatekeeper warnings.
5. Check the sidebar backup indicator. If cloud backup is unavailable, choose an encrypted backup location and keep the recovery key independently. A local backup is not an uploaded backup.
6. Open **백업·CLI 설정** and connect the bundled CLI to `~/.local/bin/keydesk`. Confirm the connection without exposing credentials:

   ```sh
   ~/.local/bin/keydesk status
   ```

Cellar creates the initial vault through its first-run flow. After unlocking, create a project and choose Development, Staging or Production. Register a string key, or select **파일 원본 보관** and choose/drop an original key file. The service field offers inline search suggestions.

![Cellar 0.7.5 demo vault](images/cellar-vault.png)

잠금 중에도 **새 키 맡기기**로 새 키나 파일을 암호화 접수할 수 있습니다. 다음 잠금 해제 때 금고에 편입되고 백업됩니다. 접수 직후에는 이 Mac에만 저장된 상태이므로 iCloud 업로드가 끝났다고 간주하지 마세요.

## Connect Codex and Claude

Install the official app first and connect its CLI. Before running the two-client recipe, confirm the prerequisites in Terminal:

```sh
python3 --version   # must be 3.11 or newer
git --version
codex --version
claude --version
```

If a command is missing, install it from the official references above, then reopen Terminal. A system Python older than 3.11 cannot run these scripts. Both AI clients are required by the default recipe below; single-client commands are shown after it. Close other client sessions while changing their configuration.

Clone the source repository to obtain the maintained setup scripts; you do not need to build the app:

```sh
git clone https://github.com/kohana-dev/keydesk.git
cd keydesk
python3 scripts/install-ai-skills.py
python3 scripts/install-auto-mcp.py
```

For only one client, use the same selection for both commands:

```sh
python3 scripts/install-ai-skills.py --client codex
python3 scripts/install-auto-mcp.py --client codex
# For Claude only, replace codex with claude.
```

Before writing, the installers check all selected targets, conflicting definitions, configuration syntax/structure and required source files. MCP setup also checks the installed Cellar helper, CLI link and selected client executables (`--version`). This does not authenticate an AI account or verify a provider key. A missing or unresponsive client stops setup before configuration writes.

On a handled installation error or keyboard interrupt, each script restores the files it changed (including prior permissions) and removes newly created target files. Existing replaced files also have private `.cellar-backup-<timestamp>` copies. The two commands are separate transactions: if MCP setup fails, successfully installed skills remain and can be reused. Correct the reported prerequisite and rerun; successful reruns are idempotent. Never delete an existing conflicting client configuration to get past an error.

Atomic writes protect individual files, but power loss or forcibly killing the installer can interrupt a multi-file setup. If rollback itself reports failure, restore the affected configuration from its backup before retrying. Do not run multiple installers or edit client configuration concurrently.

The scripts install the `keydesk` companion skill and one global repository-aware MCP connection for both clients. They preserve unrelated client settings and stop on conflicting existing definitions. Restart/reload existing client sessions once to load the new connection. Explicit skill invocation remains Codex `$keydesk` and Claude `/keydesk`.

Confirm the connection before creating a project mapping:

```sh
codex mcp list
claude mcp list
```

Codex should list `keydesk` as enabled; Claude should show `keydesk` as Connected. An Unsupported OAuth auth column in Codex is expected for this local stdio server: Cellar handles vault authentication and human approval separately.

No MCP registration is required for each project. In the repository you are developing, use a names-only `keydesk.project.json` that matches a project and variables already stored in Cellar:

```json
{
  "version": 1,
  "project": "my-app",
  "bindings": {
    "dev": {
      "OPENAI_API_KEY": "value",
      "GOOGLE_APPLICATION_CREDENTIALS": "file"
    }
  }
}
```

Create this file in the root of your actual development repository, replacing `my-app` and the example variables with the exact project and variable names you registered in Cellar. `dev`, `staging` and `prod` are environment identifiers; `Development` is the UI label for `dev`.

This file contains names and types only. It does not create, copy or expose keys. The AI should call `project_context` with its repository's absolute path, then `request_http` with the intended environment and existing value binding. Original files, SDKs and build tools use `keydesk run --files/--only`; they are not exposed as MCP file-reading tools. See [MCP setup](mcp-setup.md), [local API broker](local-api-broker.md) and [project CLI](project-cli.md).

Approve the first use in Cellar yourself. If you choose exact-request reuse, identical production requests can share the grant across Codex and Claude for five minutes and ten additional requests. The app never gives the authentication value to the MCP caller. Approved CLI/SDK processes do receive their selected credentials and require trusted tools.

### First AI connection check

Start a new Codex or Claude session in that development repository and ask:

> Use the keydesk MCP project_context tool for this repository. Confirm the project, environment and variable names only. Do not read any credential values or call a provider API yet.

The response should match your manifest. If it reports `unconfigured`, fix the manifest instead of registering another MCP server. Then request your intended supported API operation and approve it in Cellar; success is an actual provider response, not merely a listed MCP server.

### If `keydesk` is not found in Terminal

The CLI link is `~/.local/bin/keydesk`. The full-path status command above works even if this folder is not in your shell PATH. For commands using bare `keydesk`, add it for the current Terminal session:

```sh
export PATH="$HOME/.local/bin:$PATH"
keydesk status
```

To keep it for future zsh sessions, add that same export line to your existing `~/.zshrc`; preserve its other contents. The AI adapters use the full helper path and do not need this PATH change.

## Upgrade from Keydesk.app

Keep your encrypted backup and recovery key. Do not delete the vault or change the app's signing identity as part of a rename.

1. Save or cancel any open registration form, then quit the old app.
2. Install the official **Cellar.app** in `~/Applications`. Remove the old `Keydesk.app` from Applications after confirming the new app works; keep a previous copy elsewhere if desired.
3. From the source checkout, update the CLI link and exact legacy client helper paths:

   ```sh
   python3 scripts/migrate-cellar-paths.py
   python3 scripts/install-ai-skills.py --update
   python3 scripts/install-auto-mcp.py
   ```

   Existing client settings and skills are backed up before changes. For a project-local MCP configuration add `--config /absolute/path/.mcp.json` to the migration command. Conflicting non-Cellar executables/configurations are preserved.
4. Restart AI sessions that cached the old direct helper path. A global router still uses the same `keydesk` MCP name.
5. Open Cellar and authenticate. Confirm your existing projects and backup status, then run `keydesk status`.
6. If a fixed Dock icon still shows Keydesk, remove that old Dock item and drag `Cellar.app` from Finder into the Dock.

Existing vault locations, project manifests and Keychain access identity remain unchanged. Renaming the app does not migrate data to a different vault.

## Troubleshooting

- **CLI cannot connect:** open `~/Applications/Cellar.app`; check the CLI link in **백업·CLI 설정**. Unlock only when the operation needs an existing credential.
- **AI cannot see MCP tools:** reload the session after setup and check the client's `keydesk` MCP connection. Do not fall back to reading `.env` or private key contents.
- **Project is unconfigured:** fix the repository's names-only manifest. Do not select another project's production credential based on its provider.
- **Approval expired or was rejected:** stop that attempt. Start a new request only when the user is ready; do not automatically retry.
- **Backup is pending:** keep Cellar open, check iCloud availability and the actual upload status. `queued` deposits are not off-device backups.

Screenshots are from Cellar 0.7.5 in an isolated demo vault with fictional data. The UI is currently in Korean. Distribution remains beta; separate-Mac recovery and an independent security audit are not completed. See [SECURITY.md](../SECURITY.md).


## Manual first-run and system-lock verification

A clean HOME directory is not a separate macOS account: Keychain and GUI login
sessions must also be distinct. For a clean-account creation test on the same
Mac, create a **standard test user** in System Settings and log into it. Enter
account passwords and macOS authentication yourself; never send them to an AI.
Do not connect the existing Apple account for this specific empty-vault test;
otherwise automatic restore may replace the intended creation scenario.

Follow the installation steps above in that account, then check:

1. With no existing vault, Cellar creates an empty vault and opens its main screen.
2. With iCloud unavailable, the UI reports the need for a backup folder; it must
   not claim an uploaded backup. Recovery-key storage may also require manual
   handling. Keep any displayed recovery key private.
3. Lock the vault, unlock it, and authenticate in the native macOS prompt. Run
   the bundled helper's `status` command; `locked` should be `false` after success.
4. Quit and reopen Cellar. The existing vault must remain intact and require
   authentication to unlock. Cancel authentication once and check it stays locked.
5. Use only a disposable test credential if exercising storage. Keep the real
   production vault and Apple account out of this creation test.

For screen-lock and sleep testing, first unlock a disposable demo vault. Trigger
an actual macOS screen lock, unlock the **screen** yourself, and verify the vault
still requires its own unlock. Repeat with a real system sleep/wake transition.
Posting notification names in a test is not evidence of actual system sleep.

On 2026-10-13 the published Cellar 0.7.5 app was exercised in demo mode on the
maintainer's Mac. Actual screen-lock/unlock and sleep/wake notifications were
observed independently; CLI status changed from unlocked to locked and remained
locked after return. No real credentials were used. Automated tests also cover
creation without iCloud, failed recovery-key storage, and device-Keychain failure
with a successful retry. These tests substitute a Keychain and do not establish
the separate-user first-run authentication result; that manual check remains
pending until performed in a separate logged-in account.
