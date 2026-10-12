#!/usr/bin/env python3
"""Install one repository-aware user MCP connection, preserving other client configuration."""
import json,pathlib,re,subprocess,sys,tomllib,importlib.util
spec=importlib.util.spec_from_file_location('setup',pathlib.Path(__file__).with_name('install-mcp.py'));setup=importlib.util.module_from_spec(spec);spec.loader.exec_module(setup)
home=pathlib.Path.home();router=home/'.local/bin/keydesk-mcp';name='keydesk'
if not router.is_file():raise SystemExit('Run install-ai-skills.py first')
cp=home/'.codex/config.toml';lp=home/'.claude.json';sp=home/'.claude/settings.json'
c=tomllib.loads(cp.read_text()) if cp.exists() else {};l=json.loads(lp.read_text()) if lp.exists() else {};s=json.loads(sp.read_text()) if sp.exists() else {}
server={'command':sys.executable,'args':[str(router)]}
for existing in [c.get('mcp_servers',{}).get(name),l.get('mcpServers',{}).get(name)]:
 if existing and (existing.get('command')!=server['command'] or existing.get('args')!=server['args']):raise SystemExit('Conflicting keydesk server preserved; choose an explicit migration')
if name not in c.get('mcp_servers',{}):
 setup.backup(cp);cp.parent.mkdir(parents=True,exist_ok=True)
 with cp.open('a') as f:
  f.write('\n[mcp_servers.keydesk]\ncommand = '+json.dumps(server['command'])+'\nargs = '+json.dumps(server['args'])+'\nenabled_tools = ["project_context", "request_http"]\ntool_timeout_sec = 180\n')
  for tool in ['project_context','request_http']:f.write('\n[mcp_servers.keydesk.tools.'+tool+']\napproval_mode = "approve"\n')
 cp.chmod(0o600)
if name not in l.get('mcpServers',{}):
 setup.backup(lp)
 subprocess.run(['claude','mcp','add-json','--scope','user',name,json.dumps({'type':'stdio',**server})],check=True,capture_output=True)
allow=s.setdefault('permissions',{}).setdefault('allow',[])
changed=False
for tool in ['project_context','request_http']:
 p='mcp__keydesk__'+tool
 if p not in allow:allow.append(p);changed=True
if changed:setup.backup(sp);sp.parent.mkdir(parents=True,exist_ok=True);sp.write_text(json.dumps(s,ensure_ascii=False,indent=2)+'\n');sp.chmod(0o600)
print('Repository-aware Keydesk MCP installed for Codex and Claude. No project is selected by default.')
