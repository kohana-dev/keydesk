#!/usr/bin/env python3
"""Install a repository-aware Cellar MCP connection with preflight and rollback."""
import argparse
import json
import os
import pathlib
import shutil
import subprocess
import sys
from installer_support import Transaction, atomic_write, check_path


def install(client='both', home=None):
    if sys.version_info < (3, 11):
        raise ValueError('Python 3.11 or newer is required')
    import tomllib
    home = home or pathlib.Path.home()
    clients = ['codex', 'claude'] if client == 'both' else [client]
    router = home / '.local/bin/keydesk-mcp'
    helper = home / 'Applications/Cellar.app/Contents/Helpers/keydesk'
    if not router.is_file() or router.is_symlink():
        raise ValueError('Run install-ai-skills.py first; the MCP adapter is missing or invalid')
    if not helper.is_file() or not os.access(helper, os.X_OK):
        raise ValueError('Install Cellar.app in ~/Applications before connecting MCP')
    cli = home / '.local/bin/keydesk'
    if not cli.is_file() or cli.resolve() != helper.resolve():
        raise ValueError('Connect the Cellar CLI in the app settings before connecting MCP')
    executables = {}
    for name in clients:
        executable = shutil.which(name)
        if not executable:
            raise ValueError('Install the requested ' + name + ' CLI first; no settings changed')
        try:
            subprocess.run([executable, '--version'], check=True, capture_output=True, timeout=10)
        except (OSError, subprocess.SubprocessError):
            raise ValueError(name + ' CLI is unavailable or unresponsive; no settings changed') from None
        executables[name] = executable
    cp = home / '.codex/config.toml'
    lp = home / '.claude.json'
    sp = home / '.claude/settings.json'
    paths = ([cp] if 'codex' in clients else []) + ([lp, sp] if 'claude' in clients else [])
    for path in paths:
        check_path(path)
    try:
        c = tomllib.loads(cp.read_text()) if 'codex' in clients and cp.exists() else {}
        l = json.loads(lp.read_text()) if 'claude' in clients and lp.exists() else {}
        s = json.loads(sp.read_text()) if 'claude' in clients and sp.exists() else {}
        if not all(isinstance(v, dict) for v in [c, l, s]):
            raise ValueError()
        for obj, key in [(c, 'mcp_servers'), (l, 'mcpServers'), (s, 'permissions')]:
            if key in obj and not isinstance(obj[key], dict):
                raise ValueError()
        allow = s.get('permissions', {}).get('allow', [])
        if not isinstance(allow, list) or not all(isinstance(v, str) for v in allow):
            raise ValueError()
    except (ValueError, TypeError):
        raise ValueError('Invalid client configuration; preserved without changes. Fix its syntax/structure first.') from None
    server = {'command': sys.executable, 'args': [str(router)]}
    for existing in [c.get('mcp_servers', {}).get('keydesk'), l.get('mcpServers', {}).get('keydesk')]:
        if existing is not None and (not isinstance(existing, dict) or existing.get('command') != server['command'] or existing.get('args') != server['args']):
            raise ValueError('Conflicting keydesk server preserved; choose an explicit migration')
    transaction = Transaction(paths)
    try:
        if 'codex' in clients and 'keydesk' not in c.get('mcp_servers', {}):
            transaction.backup(cp)
            text = cp.read_text() if cp.exists() else ''
            text += '\n[mcp_servers.keydesk]\ncommand = ' + json.dumps(server['command']) + '\nargs = ' + json.dumps(server['args']) + '\nenabled_tools = ["project_context", "request_http"]\ntool_timeout_sec = 180\n'
            for tool in ['project_context', 'request_http']:
                text += '\n[mcp_servers.keydesk.tools.' + tool + ']\napproval_mode = "approve"\n'
            atomic_write(cp, text.encode(), 0o600)
        if 'claude' in clients:
            if 'keydesk' not in l.get('mcpServers', {}):
                transaction.backup(lp)
                subprocess.run([executables['claude'], 'mcp', 'add-json', '--scope', 'user', 'keydesk', json.dumps({'type': 'stdio', **server})], check=True, capture_output=True, timeout=30)
                registered = json.loads(lp.read_text()).get('mcpServers', {}).get('keydesk', {})
                if registered.get('command') != server['command'] or registered.get('args') != server['args']:
                    raise ValueError('Client did not register the expected connection')
                lp.chmod(0o600)
            allow = s.setdefault('permissions', {}).setdefault('allow', [])
            changed = False
            for tool in ['project_context', 'request_http']:
                permission = 'mcp__keydesk__' + tool
                if permission not in allow:
                    allow.append(permission)
                    changed = True
            if changed:
                transaction.backup(sp)
                atomic_write(sp, (json.dumps(s, ensure_ascii=False, indent=2) + '\n').encode(), 0o600)
    except (Exception, KeyboardInterrupt):
        transaction.rollback()
        raise RuntimeError('MCP installation failed; previous client settings restored. Check the CLI and rerun. Diagnostic output is withheld to protect configuration data.') from None
    print('Cellar MCP installed for ' + ', '.join(clients) + '. No default project; native approval remains required.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client', choices=['codex', 'claude', 'both'], default='both')
    args = parser.parse_args()
    try:
        install(args.client)
    except (ValueError, RuntimeError, OSError) as error:
        raise SystemExit(str(error)) from None
