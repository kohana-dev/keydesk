#!/usr/bin/env python3
"""Project-scoped Keydesk CLI adapter. Configuration contains names, never secrets."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

CONFIG_NAME = 'keydesk.project.json'
ENVIRONMENTS = {'dev', 'staging', 'prod'}

def load_config(start):
    directory = Path(start).resolve()
    for root in [directory, *directory.parents]:
        path = root / CONFIG_NAME
        if path.exists():
            if path.is_symlink() or path.stat().st_size > 65536:
                raise ValueError('Invalid project configuration')
            config = json.loads(path.read_text())
            if not isinstance(config, dict) or config.get('version') != 1:
                raise ValueError('Unsupported project configuration')
            project = config.get('project')
            if not isinstance(project, str) or not project or len(project) > 100 or '\0' in project:
                raise ValueError('Invalid project name')
            bindings = config.get('bindings', {})
            if not isinstance(bindings, dict) or not set(bindings).issubset(ENVIRONMENTS):
                raise ValueError('Invalid environments')
            for items in bindings.values():
                if not isinstance(items, dict):
                    raise ValueError('Invalid binding list')
                for name, kind in items.items():
                    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]{0,127}', name) or kind not in {'file', 'value'}:
                        raise ValueError('Invalid binding')
            config['bindings'] = bindings
            return root, config
    raise ValueError('No keydesk.project.json found in this directory or its parents')

def select_names(text, items, kind):
    names = text.split(',') if text else []
    if len(names) != len(set(names)) or any(items.get(n) != kind for n in names):
        raise ValueError('Select names and types listed in this environment configuration')
    return names

def run_arguments(config, environment, only, files, command):
    if environment not in ENVIRONMENTS:
        raise ValueError('Specify dev, staging or prod')
    items = config['bindings'].get(environment, {})
    values = select_names(only, items, 'value')
    paths = select_names(files, items, 'file')
    if command and command[0] == '--':
        command = command[1:]
    if not command or not (values or paths):
        raise ValueError('Select --only/--files and provide a command after --')
    args = ['run', '--project', config['project'], '--env', environment]
    if values:
        args += ['--only', ','.join(values)]
    if paths:
        args += ['--files', ','.join(paths)]
    return args + ['--'] + command

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    sub.add_parser('describe', help='Print configured project and variable names, never values')
    sub.add_parser('imports', help='List locally recorded file migration receipts, not vault contents')
    sub.add_parser('connections', help='List configured MCP targets and known binding names, never values')
    sub.add_parser('status', help='Query vault lock, deposit and backup status')
    run = sub.add_parser('run', help='Use the signed CLI; native approval still applies')
    run.add_argument('--env', required=True, choices=sorted(ENVIRONMENTS))
    run.add_argument('--only')
    run.add_argument('--files')
    run.add_argument('command', nargs=argparse.REMAINDER)
    request = sub.add_parser('request', help='Call an official API through the local broker; native approval still applies')
    request.add_argument('--env', required=True, choices=sorted(ENVIRONMENTS))
    request.add_argument('--key', required=True)
    request.add_argument('--method', choices=['GET','HEAD','POST','PUT','PATCH','DELETE'], default='GET')
    request.add_argument('--url', required=True)
    request.add_argument('--body-file')
    store = sub.add_parser('store-file', help='Deposit a file without reading it into AI output')
    store.add_argument('--env', required=True, choices=sorted(ENVIRONMENTS))
    store.add_argument('--name', required=True)
    store.add_argument('--from-file', required=True)
    args = parser.parse_args()
    cli = Path.home() / '.local/bin/keydesk'
    try:
        if args.action == 'connections':
            registry = Path.home() / '.config/keydesk/mcp-connections.json'
            if registry.is_symlink() or (registry.exists() and registry.stat().st_size > 65536):
                raise ValueError('Invalid MCP registry')
            rows = json.loads(registry.read_text()) if registry.exists() else []
            allowed = {'server', 'project', 'projectId', 'environment', 'clients', 'knownBindings'}
            if not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
                raise ValueError('Invalid MCP registry')
            print(json.dumps([{k: v for k, v in row.items() if k in allowed} for row in rows], ensure_ascii=False, indent=2))
            return 0
        if args.action == 'imports':
            registry = Path.home() / '.config/keydesk/imported-files.json'
            if registry.is_symlink() or (registry.exists() and registry.stat().st_size > 65536):
                raise ValueError('Invalid receipt registry')
            rows = json.loads(registry.read_text()) if registry.exists() else []
            if not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
                raise ValueError('Invalid receipt registry')
            allowed = {'project', 'environment', 'variable', 'kind', 'state'}
            print(json.dumps([{k: v for k, v in row.items() if k in allowed and isinstance(v, str)} for row in rows], ensure_ascii=False, indent=2))
            return 0
        if args.action == 'status':
            invocation = ['status']
        else:
            root, config = load_config(Path.cwd())
            if args.action == 'describe':
                print(json.dumps({'version': 1, 'project': config['project'], 'bindings': config['bindings']}, ensure_ascii=False, indent=2))
                return 0
            if args.action == 'run':
                invocation = run_arguments(config, args.env, args.only, args.files, args.command)
            elif args.action == 'request':
                selected = select_names(args.key, config['bindings'].get(args.env, {}), 'value')
                if len(selected) != 1:
                    raise ValueError('Select exactly one value key')
                invocation = ['request', '--project', config['project'], '--env', args.env, '--key', selected[0], '--method', args.method, '--url', args.url]
                if args.body_file:
                    invocation += ['--body-file', str(Path(args.body_file).absolute())]
            else:
                select_names(args.name, config['bindings'].get(args.env, {}), 'file')
                invocation = ['store-file', '--project', config['project'], '--env', args.env, '--name', args.name, '--from-file', str(Path(args.from_file).absolute())]
        if not cli.exists():
            raise ValueError('Install the signed Keydesk CLI first')
        # Argument array, no shell interpolation. Child streams retain Keydesk output filtering.
        return subprocess.call([str(cli), *invocation])
    except (ValueError, OSError):
        print('Keydesk project command failed: check configuration, selected bindings and CLI installation. No secret was printed.', file=sys.stderr)
        return 2

if __name__ == '__main__':
    sys.exit(main())
