#!/usr/bin/env python3
"""Install Cellar companion skills and adapters with preflight and rollback."""
import argparse
import pathlib
import sys
from installer_support import Transaction, atomic_write, check_path


def skill_targets(home, client='both'):
    """Canonical selected-client skills plus existing Cellar aliases only."""
    clients = ['codex', 'claude'] if client == 'both' else [client]
    targets = [home / f'.{c}/skills/keydesk/SKILL.md' for c in clients]
    targets += [home / f'.{c}/skills/cellar/SKILL.md' for c in clients
                if (home / f'.{c}/skills/cellar/SKILL.md').exists() or (home / f'.{c}/skills/cellar/SKILL.md').is_symlink()]
    targets += [home / f'.agents/skills/{alias}/SKILL.md' for alias in ['keydesk', 'cellar']
                if (home / f'.agents/skills/{alias}/SKILL.md').exists() or (home / f'.agents/skills/{alias}/SKILL.md').is_symlink()]
    return targets


def skill_bytes(source, target):
    data = source.read_bytes()
    if target.parent.name == 'cellar':
        # Keep the existing explicit $cellar / /cellar invocation name.
        if not data.startswith(b'---\nname: keydesk\n'):
            raise ValueError('Unexpected maintained skill frontmatter')
        data = data.replace(b'---\nname: keydesk\n', b'---\nname: cellar\n', 1)
    return data


def install(client='both', update=False, home=None):
    if sys.version_info < (3, 11):
        raise ValueError('Python 3.11 or newer is required')
    home = home or pathlib.Path.home()
    root = pathlib.Path(__file__).resolve().parent.parent
    source = root / 'integrations/skills/keydesk/SKILL.md'
    plan = [(source, target, 0o644) for target in skill_targets(home, client)]
    plan += [(root / 'scripts' / src, home / '.local/bin' / dst, 0o755) for src, dst in [
        ('keydesk-project.py', 'keydesk-project'), ('install-mcp.py', 'keydesk-connect'), ('keydesk-mcp.py', 'keydesk-mcp')]]
    pending = []
    for src, target, mode in plan:
        if not src.is_file() or src.is_symlink():
            raise ValueError('A required source file is missing or invalid; use a complete source checkout')
        check_path(target)
        parent = target.parent
        while parent != home and parent != parent.parent:
            if parent.is_symlink():
                raise ValueError('A skill or adapter target directory is a symlink; preserve it and resolve manually')
            parent = parent.parent
        data = skill_bytes(src, target) if src == source else src.read_bytes()
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
