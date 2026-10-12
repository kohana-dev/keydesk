#!/usr/bin/env python3
"""Install Cellar companion skills and adapters with preflight and rollback."""
import argparse
import pathlib
import sys
from installer_support import Transaction, atomic_write, check_path


def install(client='both', update=False, home=None):
    if sys.version_info < (3, 11):
        raise ValueError('Python 3.11 or newer is required')
    home = home or pathlib.Path.home()
    root = pathlib.Path(__file__).resolve().parent.parent
    source = root / 'integrations/skills/keydesk/SKILL.md'
    clients = ['codex', 'claude'] if client == 'both' else [client]
    plan = [(source, home / f'.{c}/skills/keydesk/SKILL.md', 0o644) for c in clients]
    plan += [(root / 'scripts' / src, home / '.local/bin' / dst, 0o755) for src, dst in [
        ('keydesk-project.py', 'keydesk-project'), ('install-mcp.py', 'keydesk-connect'), ('keydesk-mcp.py', 'keydesk-mcp')]]
    pending = []
    for src, target, mode in plan:
        if not src.is_file() or src.is_symlink():
            raise ValueError('A required source file is missing or invalid; use a complete source checkout')
        check_path(target)
        data = src.read_bytes()
        if target.exists() and target.read_bytes() != data and not update:
            raise ValueError('Conflicting skill or adapter preserved; use --update to back up and replace')
        if not target.exists() or target.read_bytes() != data or target.stat().st_mode & 0o777 != mode:
            pending.append((target, data, mode))
    transaction = Transaction([target for target, _, _ in pending])
    try:
        for target, data, mode in pending:
            transaction.backup(target)
            atomic_write(target, data, mode)
    except (Exception, KeyboardInterrupt):
        transaction.rollback()
        raise RuntimeError('Skill installation failed; previous files restored. Correct the cause and rerun.') from None
    print('Cellar companion skills and adapters installed. No account or key access; native approval remains required.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client', choices=['codex', 'claude', 'both'], default='both')
    parser.add_argument('--update', action='store_true', help='Back up and replace existing skills/adapters')
    args = parser.parse_args()
    try:
        install(args.client, args.update)
    except (ValueError, RuntimeError, OSError) as error:
        raise SystemExit(str(error)) from None
