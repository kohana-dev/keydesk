#!/usr/bin/env python3
"""Register one explicit Keydesk project/environment in both AI clients. No secrets."""
import argparse, datetime, json, pathlib, re, shutil, subprocess, tomllib, uuid

def backup(path):
    if path.exists():
        target=path.with_name(path.name+'.keydesk-backup-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
        shutil.copy2(path,target); target.chmod(0o600)

def install(project, environment, name, label, clients, home):
    project=str(uuid.UUID(project)).upper()
    if environment not in {'dev','staging','prod'} or not re.fullmatch(r'keydesk-[a-z0-9-]{1,60}',name):
        raise ValueError('Use an explicit environment and keydesk-prefixed server name')
    helper=home/'Applications/Cellar.app/Contents/Helpers/keydesk'
    if not helper.is_file():raise ValueError('Install the signed Keydesk app first')
    server={'command':str(helper),'args':['mcp','--project',project,'--env',environment]}
    codex_path=home/'.codex/config.toml';claude_path=home/'.claude.json'
    registry_path=home/'.config/keydesk/mcp-connections.json'
    registry=json.loads(registry_path.read_text()) if registry_path.exists() else []
    if not isinstance(registry,list):raise ValueError('Invalid metadata registry')
    old=next((r for r in registry if r.get('server')==name),None)
    if old and (old.get('projectId')!=project or old.get('environment')!=environment):raise ValueError('Conflicting registered target preserved')
    for client in clients:
        if client=='codex':
            config=tomllib.loads(codex_path.read_text()) if codex_path.exists() else {}
            existing=config.get('mcp_servers',{}).get(name)
        else:
            config=json.loads(claude_path.read_text()) if claude_path.exists() else {}
            existing=config.get('mcpServers',{}).get(name)
        if existing and (existing.get('command')!=server['command'] or existing.get('args')!=server['args']):
            raise ValueError('Conflicting MCP server preserved')
        if not shutil.which(client):raise ValueError('Install requested AI client first')
    for client in clients:
        if client=='codex':
            config=tomllib.loads(codex_path.read_text()) if codex_path.exists() else {}
            existing=config.get('mcp_servers',{}).get(name)
            if not existing:
                backup(codex_path)
                codex_path.parent.mkdir(parents=True,exist_ok=True)
                with codex_path.open('a') as f:
                    f.write('\n[mcp_servers.'+name+']\ncommand = '+json.dumps(server['command'])+'\nargs = '+json.dumps(server['args'])+'\nenabled_tools = ["request_http"]\ntool_timeout_sec = 180\n')
                    f.write('\n[mcp_servers.'+name+'.tools.request_http]\napproval_mode = "approve"\n')
                # Only request_http is available; the broker still requires human approval.
                codex_path.chmod(0o600)
        else:
            config=json.loads(claude_path.read_text()) if claude_path.exists() else {}
            if not config.get('mcpServers',{}).get(name):
                backup(claude_path)
                subprocess.run(['claude','mcp','add-json','--scope','user',name,json.dumps({'type':'stdio',**server})],check=True,capture_output=True)
            settings_path=home/'.claude/settings.json'
            settings=json.loads(settings_path.read_text()) if settings_path.exists() else {}
            permission='mcp__'+name+'__request_http'
            allow=settings.setdefault('permissions',{}).setdefault('allow',[])
            if permission not in allow:
                backup(settings_path);allow.append(permission);settings_path.parent.mkdir(parents=True,exist_ok=True)
                settings_path.write_text(json.dumps(settings,ensure_ascii=False,indent=2)+'\n');settings_path.chmod(0o600)
    row={'server':name,'project':label,'projectId':project,'environment':environment,'clients':sorted(set(clients+(old or {}).get('clients',[]))),'knownBindings':(old or {}).get('knownBindings',{})}
    registry=[r for r in registry if r.get('server')!=name]+[row]
    registry_path.parent.mkdir(parents=True,exist_ok=True);backup(registry_path)
    registry_path.write_text(json.dumps(registry,ensure_ascii=False,indent=2)+'\n');registry_path.chmod(0o600)
    return row

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--project-id',required=True);p.add_argument('--env',required=True,choices=['dev','staging','prod'])
    p.add_argument('--name',required=True);p.add_argument('--project-name',required=True)
    p.add_argument('--client',choices=['codex','claude','both'],default='both');a=p.parse_args()
    try:
        row=install(a.project_id,a.env,a.name,a.project_name,['codex','claude'] if a.client=='both' else [a.client],pathlib.Path.home())
        print(json.dumps(row,ensure_ascii=False))
    except (ValueError,OSError,subprocess.SubprocessError):
        raise SystemExit('MCP setup failed; inspect client configuration. Credentials were not accessed. Backups are private.')
