#!/usr/bin/env python3
import importlib.util,json,pathlib,tempfile,unittest
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('setup',pathlib.Path(__file__).with_name('install-mcp.py'));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
PROJECT='00000000-0000-4000-8000-000000000001';NAME='keydesk-example-dev'
class SetupTests(unittest.TestCase):
 def test_codex_appends_only_target_and_leaves_other_servers_intact(self):
  with tempfile.TemporaryDirectory() as d:
   home=pathlib.Path(d);helper=home/'Applications/Keydesk.app/Contents/Helpers/keydesk';helper.parent.mkdir(parents=True);helper.touch()
   p=home/'.codex/config.toml';p.parent.mkdir();original='model = "existing"\n[mcp_servers.example]\ncommand = "existing-helper"\nargs = []\n';p.write_text(original)
   with patch.object(m.shutil,'which',return_value='/bin/client'),patch.object(m.subprocess,'run') as run:
    m.install(PROJECT,'dev',NAME,'Example',['codex'],home);first=p.read_bytes()
    m.install(PROJECT,'dev',NAME,'Example',['codex'],home)
    run.assert_not_called()
   self.assertEqual(p.read_bytes(),first);self.assertTrue(p.read_text().startswith(original))
   config=m.tomllib.loads(p.read_text());self.assertEqual(config['mcp_servers']['example']['args'],[])
   server=config['mcp_servers'][NAME];self.assertEqual(server['enabled_tools'],['request_http']);self.assertEqual(server['tools']['request_http']['approval_mode'],'approve')
 def test_invalid_target_cannot_modify_configuration(self):
  with tempfile.TemporaryDirectory() as d:
   home=pathlib.Path(d)
   for project,env,name in [('not-uuid','dev',NAME),(PROJECT,'wrong',NAME),(PROJECT,'dev','other')]:
    with patch.object(m.subprocess,'run') as run:
     with self.assertRaises(ValueError):m.install(project,env,name,'Example',['codex','claude'],home)
     run.assert_not_called()
   self.assertEqual(list(home.iterdir()),[])
 def test_conflicting_server_preflight_preserves_both_clients(self):
  with tempfile.TemporaryDirectory() as d:
   home=pathlib.Path(d);helper=home/'Applications/Keydesk.app/Contents/Helpers/keydesk';helper.parent.mkdir(parents=True);helper.touch()
   c=home/'.claude.json';raw=json.dumps({'mcpServers':{NAME:{'command':'another','args':[]}},'unrelated':'retain'});c.write_text(raw)
   with patch.object(m.shutil,'which',return_value='/bin/client'),patch.object(m.subprocess,'run') as run:
    with self.assertRaises(ValueError):m.install(PROJECT,'dev',NAME,'Example',['codex','claude'],home)
    run.assert_not_called()
   self.assertEqual(c.read_text(),raw);self.assertFalse((home/'.codex/config.toml').exists())
 def test_scoped_permissions_preserve_unrelated_settings_and_idempotence(self):
  with tempfile.TemporaryDirectory() as d:
   home=pathlib.Path(d);helper=home/'Applications/Keydesk.app/Contents/Helpers/keydesk';helper.parent.mkdir(parents=True);helper.touch()
   c=home/'.claude.json';c.write_text(json.dumps({'mcpServers':{NAME:{'command':str(helper),'args':['mcp','--project',PROJECT,'--env','dev']}},'unrelated':'retain'}))
   s=home/'.claude/settings.json';s.parent.mkdir();s.write_text(json.dumps({'permissions':{'allow':['Read'],'deny':['Bash']},'theme':'dark'}))
   with patch.object(m.shutil,'which',return_value='/bin/client'),patch.object(m.subprocess,'run') as run:
    for _ in range(2):m.install(PROJECT,'dev',NAME,'Example',['claude'],home)
    run.assert_not_called()
   settings=json.loads(s.read_text());self.assertEqual(settings['permissions']['allow'],['Read','mcp__'+NAME+'__request_http']);self.assertEqual(settings['permissions']['deny'],['Bash']);self.assertEqual(settings['theme'],'dark')
   self.assertEqual(json.loads(c.read_text())['unrelated'],'retain');self.assertEqual(len(json.loads((home/'.config/keydesk/mcp-connections.json').read_text())),1)
   self.assertEqual(s.stat().st_mode & 0o777,0o600)
unittest.main()
