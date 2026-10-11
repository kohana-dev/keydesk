#!/usr/bin/env python3
"""Install only the maintained skill, preserving conflicting personal files."""
import argparse, pathlib, shutil, datetime
p=argparse.ArgumentParser();p.add_argument('--client',choices=['codex','claude','both'],default='both');p.add_argument('--update',action='store_true',help='Back up and replace an existing Keydesk skill');a=p.parse_args()
source=pathlib.Path(__file__).resolve().parent.parent/'integrations/skills/keydesk/SKILL.md'
targets=[pathlib.Path.home()/f'.{c}/skills/keydesk/SKILL.md' for c in (['codex','claude'] if a.client=='both' else [a.client])]
for target in targets:
 if target.exists() and target.read_bytes()!=source.read_bytes() and not a.update:raise SystemExit(f'Conflicting skill preserved: {target}; use --update to back up and replace')
for target in targets:
 target.parent.mkdir(parents=True,exist_ok=True)
 if target.exists() and target.read_bytes()!=source.read_bytes():
  backup=target.with_name('SKILL.md.backup-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'));shutil.copyfile(target,backup)
 shutil.copyfile(source,target)
print('Keydesk companion skills installed; no account or key access.')
