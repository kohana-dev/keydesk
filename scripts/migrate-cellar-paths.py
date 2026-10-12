#!/usr/bin/env python3
"""Migrate only exact legacy app helper paths; preserve all other client settings."""
import argparse
import datetime
import json
import os
from pathlib import Path
import shutil
import tomllib


def migrate(path, home):
    if not path.exists():
        return False
    old = str(home / 'Applications/Keydesk.app/Contents/Helpers/keydesk')
    new = str(home / 'Applications/Cellar.app/Contents/Helpers/keydesk')
    text = path.read_text()
    parser = tomllib.loads if path.suffix == '.toml' else json.loads
    before = parser(text)
    # Replace quoted path tokens, never broad Keydesk strings or secret values.
    updated = text.replace(json.dumps(old), json.dumps(new))
    if path.suffix == '.toml':
        updated = updated.replace("'" + old + "'", "'" + new + "'")
    if updated == text:
        return False
    expected = json.loads(json.dumps(before).replace(json.dumps(old), json.dumps(new)))
    if parser(updated) != expected:
        raise ValueError('Configuration migration would change unrelated settings')
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    backup = path.with_name(path.name + '.cellar-backup-' + stamp)
    shutil.copy2(path, backup)
    backup.chmod(0o600)
    temp = path.with_name(path.name + '.cellar-stage-' + stamp)
    try:
        temp.write_text(updated)
        temp.chmod(path.stat().st_mode & 0o777)
        os.replace(temp, path)
    finally:
        if temp.exists():
            temp.unlink()
    return True


def migrate_cli(home):
    cli = home / '.local/bin/keydesk'
    old = home / 'Applications/Keydesk.app/Contents/Helpers/keydesk'
    new = home / 'Applications/Cellar.app/Contents/Helpers/keydesk'
    if not new.is_file():
        raise ValueError('Install Cellar.app before migrating the CLI')
    if cli.is_symlink() and os.readlink(cli) == str(new):
        return False
    if cli.exists() or cli.is_symlink():
        if not cli.is_symlink() or os.readlink(cli) != str(old):
            raise ValueError('Conflicting CLI preserved')
    cli.parent.mkdir(parents=True, exist_ok=True)
    staged = cli.with_name('keydesk.cellar-stage')
    staged.symlink_to(new)
    os.replace(staged, cli)
    return True


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', action='append', type=Path, default=[], help='Additional .mcp.json or client configuration')
    args = parser.parse_args()
    home = Path.home()
    cli_changed = migrate_cli(home)
    paths = [home / '.codex/config.toml', home / '.claude.json', *args.config]
    count = sum(migrate(path, home) for path in dict.fromkeys(paths))
    print(json.dumps({'configs_updated': count, 'cli_updated': cli_changed, 'app': 'Cellar.app', 'credential_values_read': False}))
