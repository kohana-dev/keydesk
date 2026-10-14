# Install Cellar / Cellar 설치 안내

Cellar 0.7.12 adds a login launch switch in app Settings. Google Drive for desktop remains available as an encrypted backup location alongside iCloud Drive. / 0.7.12는 앱 설정에 로그인 시 자동 실행 스위치를 추가합니다. iCloud Drive와 Google Drive 동기화 폴더를 암호화 백업 위치로 선택할 수 있습니다.

The official app is **Cellar.app**, with a **Cellar** executable. The `keydesk` CLI, MCP server and companion skill names stay compatible with earlier installations.

## Requirements

- Apple Silicon Mac with macOS 14 or later. The current release does not include Intel binaries.
- No Apple Developer membership is required to install the official signed, notarized app.
- For iCloud backup and recovery: the same Apple account, iCloud Drive and iCloud Keychain enabled. Check upload status; choosing an iCloud folder alone does not prove the file has uploaded.
- For optional Google Drive backups: install [Google Drive for desktop](https://support.google.com/drive/answer/10838124?hl=en), sign in to your account, and select an actual synced folder in Cellar. Drive for desktop handles uploads; Cellar does not sign in to Google or use the Drive API.
- For AI setup: Git, Python 3.11+, the selected AI CLI(s) installed (both for the default recipe). Sign in to each selected AI client before asking it to work. The app itself does not require Git or Python.
- Official setup references: [Python for macOS](https://www.python.org/downloads/macos/), [Git for macOS](https://git-scm.com/downloads/mac), [Codex CLI](https://developers.openai.com/codex/cli/) and [Claude Code setup](https://code.claude.com/docs/en/setup).

## App language / 앱 언어

Cellar 0.7.7 supports English and 한국어. Open **Cellar → Settings → App language**
and select **System**, **한국어**, or **English**. The interface changes immediately
and the choice is remembered after restarting. Your saved project names, key names,
and vault contents are preserved. Settings are available while the vault is locked.

Cellar 0.7.7부터 한국어와 영어를 지원합니다. **Cellar → 설정 → 앱 언어**에서
**시스템 설정**, **한국어**, **English**를 선택하세요. 변경은 바로 적용되며,
다시 실행해도 유지됩니다. 저장한 프로젝트·키 이름과 금고 내용은 유지됩니다.
금고를 잠근 상태에서도 설정을 열 수 있습니다.

## Launch at login / 로그인 시 자동 실행

In Cellar 0.7.12 or later, open **Cellar → Settings** (⌘,) and turn **Launch at login** on or off. This changes the macOS login item registration and is available while the vault is locked. Cellar reads the current macOS setting; it does not turn the option back on after you disable it in System Settings. If macOS requires approval, use the **Open Login Items Settings** button and allow Cellar there. Starting the app at login keeps the vault locked until you authenticate.

Cellar 0.7.12부터 **Cellar → 설정**(⌘,)에서 **로그인 시 자동 실행**을 켜거나 끌 수 있습니다. macOS의 실제 로그인 항목 등록을 변경하며 금고가 잠겨 있어도 설정할 수 있습니다. 시스템 설정에서 꺼둔 항목을 앱이 임의로 다시 켜지 않습니다. macOS 승인이 필요하다고 표시되면 **로그인 항목 설정 열기**에서 Cellar를 허용하세요. 로그인할 때 앱이 실행되어도 금고는 인증 전까지 잠겨 있습니다.

## Updates and bug reports / 업데이트와 버그 제보

Cellar 0.7.8 adds these controls to **Cellar → Settings** (⌘,). They are
available while locked. **Check for updates** reads only the official public
GitHub release when clicked; it never sends vault contents or installs an update.
If a newer release is available, open its official download page, verify its
checksum, quit Cellar, and replace the app in `~/Applications`.

**Write a bug report** collects only what you type. App version/build, macOS
version, and architecture are optional and visible before inclusion. Review
the exact title/body, confirm that it contains no secrets or personal data, and
choose **Open GitHub draft**. This immediately passes the reviewed content to
GitHub in the browser URL, before public submission. Browser history or browser
sync may retain that URL.
Sign in and submit it yourself on GitHub to publish it. No report is posted
automatically, and logs, screenshots, key values, project names and paths are
never attached. Common secret patterns are blocked locally, but you must check
the full report. Security vulnerabilities use the separate private report link.
Sentry and automatic crash/analytics collection are not included.

Cellar 0.7.9 adds the [privacy policy](https://www.kohanacloud.com/cellar/en/privacy)
and [terms of use](https://www.kohanacloud.com/cellar/en/terms) to Settings and the
privacy policy to the report composer and review screen.

0.7.8의 **Cellar → 설정**(⌘,)에서 **업데이트 확인** 또는 **버그 제보 작성**을
선택하세요. 금고가 잠겨 있어도 사용할 수 있습니다. 업데이트는 버튼을 누를
때만 확인하고, 새 버전은 체크섬 확인 후 직접 앱을 교체합니다. 버그 제보는
작성 → 전체 내용 검토 → 비밀정보·개인 정보 없음 확인 → GitHub 초안 열기
순서입니다. 초안을 여는 즉시 검토한 내용이 URL로 GitHub에 전달되며, 브라우저
방문 기록이나 동기화에 남을 수 있습니다. GitHub에서 직접 제출해야 공개됩니다. 앱·OS 정보는 선택 사항이며
키·금고·로그·스크린샷은 자동 첨부하지 않습니다. 보안 문제는 비공개 제보를
사용하세요.

0.7.9 설정에서 [개인정보 처리방침](https://www.kohanacloud.com/cellar/privacy)과
[이용약관](https://www.kohanacloud.com/cellar/terms)을 확인할 수 있습니다.

## Download and install

1. Open the [latest release](https://github.com/kohana-dev/keydesk/releases/latest). Download its `Cellar-<version>-macOS-arm64.zip` and `SHA256SUMS.txt` into the same folder.
2. Verify the checksum in that download folder:

   ```sh
   shasum -a 256 -c SHA256SUMS.txt
   ```

   Continue only when the ZIP reports `OK`.
3. Unzip and move **Cellar.app** into your user Applications folder, **`~/Applications`**. In Finder, choose **Go → Go to Folder** and enter `~/Applications`; create the folder if needed. The AI installers currently expect this location. `/Applications` can run the app, but is not the path used by these setup scripts.
4. Open Cellar normally. On first launch, choose to create a new vault or restore a backup; if an iCloud backup is found, choose that copy or a newer file from another location. Follow macOS authentication when prompted. Do not bypass Gatekeeper warnings.
5. Check the sidebar backup indicator. If cloud backup is unavailable, choose an encrypted backup location and keep the recovery key independently. A local backup is not an uploaded backup.
6. Open **백업·CLI 설정** and connect the bundled CLI to `~/.local/bin/keydesk`. Confirm the connection without exposing credentials:

   ```sh
   ~/.local/bin/keydesk status
   ```

Cellar creates the initial vault through its first-run flow. After unlocking, create a project and choose Development, Staging or Production. Register a string key, or select **파일 원본 보관** and choose/drop an original key file. The service field offers inline search suggestions.

![Cellar 0.7.5 demo vault](images/cellar-vault.png)

잠금 중에도 **새 키 맡기기**로 새 키나 파일을 암호화 접수할 수 있습니다. 다음 잠금 해제 때 금고에 편입되고 백업됩니다. 접수 직후에는 이 Mac에만 저장된 상태이므로 클라우드 업로드가 끝났다고 간주하지 마세요.

## Backup location and recovery / 백업 위치와 복원

Open **Backup & CLI → Choose backup location** and choose **iCloud Drive**,
**Google Drive**, or **Other folder / external disk…**. Your existing iCloud backup setting stays
in place until you select a different location.

For Google Drive:

1. Install Drive for desktop and sign in before choosing the backup location.
   On macOS, enable Google Drive in Finder if prompted. See Google's
   [macOS instructions](https://support.google.com/drive/answer/12178485?hl=en).
2. In Cellar, choose **Backup & CLI → Choose backup location → Google Drive**.
   Select a folder that Drive for desktop actually syncs. A private folder such
   as **My Drive/CellarBackups** keeps backups separate from other files. A folder
   named “Google Drive” is not automatically synced; mirrored folders can also
   be stored at a custom location.
3. Cellar writes and verifies the encrypted `.keydesk` backup in that folder.
   This confirms file storage, not upload completion. Check **Sync status** in
   Google Drive for desktop and resolve any paused sync, account, storage, or
   upload errors there. Keep cloud sync enabled until the backup has uploaded.
4. For reliable local access to streamed backups, make the backup folder
   **Available offline** in Finder. This also applies to new files in that folder;
   see Google's [offline instructions](https://support.google.com/drive/answer/2375012?hl=en).

The recovery key is still stored in **iCloud Keychain**, when available, and can
be viewed from **Backup & CLI → Show recovery key** after authentication. Keep a
separate safe copy when iCloud Keychain is unavailable or for an independent
recovery route. Cellar does not put a plaintext recovery key in Google Drive.

Google Drive recovery is manual: download the required `.keydesk` backup and
keep its matching recovery key ready. On a Mac or user account without an
existing Cellar vault, use **Restore encrypted backup file**, choose that downloaded
file, and enter the recovery key. An existing vault is preserved; use **Verify
backup recovery** there to check the file and key without replacing it. After
restoring a Google Drive backup, automatic backup is unconfigured until you
select this Mac's sync folder again in **Backup & CLI**. The old Mac's saved path
and folder access are not reused. Actual Google account sync and recovery on a
separate Mac have not been verified by the local tests.

**백업·CLI 설정 → 백업 위치 선택**에서 **iCloud Drive**, **Google Drive** 또는
**다른 폴더 / 외장 디스크…**를 선택하세요. Google Drive를 쓰려면 먼저 Drive for desktop을
설치하고 로그인한 뒤 실제 동기화되는 폴더를 선택하세요. 예를 들어 내 드라이브의
비공유 **CellarBackups** 폴더를 사용할 수 있습니다. 앱의 저장·검증 성공은
업로드 완료를 뜻하지 않으므로 Google Drive의 **동기화 상태**를 확인하세요.
스트리밍 폴더는 Finder에서 **오프라인 사용 가능**으로 지정할 수 있습니다.

복구 키는 계속 iCloud 키체인 또는 사용자의 별도 보관 경로를 사용하며, 앱이
평문 복구 키를 Google Drive에 저장하지 않습니다. 수동 복원은 내려받은
`.keydesk` 파일과 해당 복구 키로 **암호화 백업 파일 복원**에서 진행합니다. 기존
금고가 있으면 덮어쓰지 않고 **백업 복구 검증**으로 확인할 수 있습니다.
Google Drive 백업을 복원한 뒤에는 이 Mac의 동기화 폴더를 다시 선택해야 자동
백업이 재개됩니다. 실제 Google 계정의 동기화와 다른 Mac 복원은 별도 검증이
필요합니다.

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
- **Backup is pending:** keep Cellar open and check the selected backup folder. For iCloud, check the app's upload status and Apple account availability; for Google Drive, check Drive for desktop's Sync status and confirm that the chosen folder still syncs. `queued` deposits are not off-device backups.

The Korean screenshots shown here are from Cellar 0.7.5 in an isolated demo vault with fictional data. Cellar 0.7.7 supports both Korean and English; choose the app language in Settings. Distribution remains beta; separate-Mac recovery and an independent security audit are not completed. See [SECURITY.md](../SECURITY.md).


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
