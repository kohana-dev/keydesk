#!/usr/bin/env python3
"""Verify maintained Cellar skills and installed adapters, never credentials."""
import argparse
import datetime
import hashlib
import importlib.util
import json
import pathlib


def verify(home=None, client='both'):
    root = pathlib.Path(__file__).resolve().parent.parent
    home = home or pathlib.Path.home()
    spec = importlib.util.spec_from_file_location('skill_installer', root / 'scripts/install-ai-skills.py')
    installer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(installer)
    source = root / 'integrations/skills/keydesk/SKILL.md'
    targets = installer.skill_targets(home, client)
    checks = []
    for target in targets:
        expected = installer.skill_bytes(source, target)
        match = target.is_file() and not target.is_symlink() and target.read_bytes() == expected
        checks.append({'path': str(target), 'sourceMatch': match,
                       'sha256': hashlib.sha256(expected).hexdigest()})
    adapters = []
    for src, name in [('keydesk-project.py', 'keydesk-project'), ('install-mcp.py', 'keydesk-connect'), ('keydesk-mcp.py', 'keydesk-mcp')]:
        target = home / '.local/bin' / name
        match = target.is_file() and not target.is_symlink() and target.read_bytes() == (root / 'scripts' / src).read_bytes() and target.stat().st_mode & 0o777 == 0o755
        adapters.append({'path': str(target), 'sourceMatch': match})
    return {'checked_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'skills': checks, 'adapters': adapters,
            'source_matches_installed_skills': all(row['sourceMatch'] for row in checks),
            'allPassed': all(row['sourceMatch'] for row in checks + adapters),
            'real_ai_automatic_invocation_verified': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client', choices=['codex', 'claude', 'both'], default='both')
    parser.add_argument('--report', type=pathlib.Path)
    args = parser.parse_args()
    report = verify(client=args.client)
    output = args.report or pathlib.Path(__file__).resolve().parent.parent / 'artifacts/skill-installation-verification.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + '\n')
    print('CELLAR_SKILLS_AND_ADAPTERS_SOURCE_MATCH_' + ('PASS' if report['allPassed'] else 'FAIL'))
    raise SystemExit(0 if report['allPassed'] else 1)
