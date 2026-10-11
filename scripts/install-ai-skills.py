#!/usr/bin/env python3
"""Install only the maintained skill, preserving conflicting personal files."""
import argparse, pathlib, shutil
p=argparse.ArgumentParser();p.add_argument('--client',choices=['codex','claude','both'],default='both');a=p.parse_args()
source=pathlib.Path(__file__).resolve().parent.parent/'integrations/skills/keydesk/SKILL.md'
targets=[pathlib.Path.home()/f'.{c}/skills/keydesk/SKILL.md' for c in (['codex','claude'] if a.client=='both' else [a.client])]
for target in targets:
 if target.exists() and target.read_bytes()!=source.read_bytes():raise SystemExit(f'Conflicting skill preserved: {target}')
for target in targets:
 target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
print('Keydesk companion skills installed; no account or key access.')
