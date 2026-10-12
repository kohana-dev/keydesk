#!/usr/bin/env python3
import importlib.util,json,pathlib,subprocess,tempfile,unittest
from unittest.mock import Mock
spec=importlib.util.spec_from_file_location('router',pathlib.Path(__file__).with_name('keydesk-mcp.py'));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class RouterTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.home=pathlib.Path(self.temp.name);self.repo=self.home/'Example';self.repo.mkdir()
  self.config={'version':1,'project':'Example','bindings':{'dev':{'TOKEN':'value','KEYFILE':'file'},'prod':{'PROD_TOKEN':'value'}}}
  (self.repo/'keydesk.project.json').write_text(json.dumps(self.config))
  self.args={'repository':str(self.repo),'environment':'dev','key':'TOKEN','method':'POST','url':'https://api.cloudflare.com/test','body':'{"text":"x"}'}
 def tearDown(self):self.temp.cleanup()
 def test_nested_repository_and_second_project_are_independent(self):
  nested=self.repo/'src';nested.mkdir();self.assertEqual(m.resolve(str(nested),home=self.home)['project'],'Example')
  other=self.home/'Other';other.mkdir();(other/'keydesk.project.json').write_text(json.dumps({'version':1,'project':'Other','bindings':{'dev':{'OTHER_TOKEN':'value'}}}))
  self.assertEqual(m.resolve(str(other),home=self.home)['bindings'],{'dev':{'OTHER_TOKEN':'value'}})
  with self.assertRaises(ValueError):m.validate_request({**self.args,'repository':str(other)},self.home)
 def test_no_environment_or_provider_fallback(self):
  for overrides in [{'environment':'prod'},{'key':'KEYFILE'},{'key':'MISSING'},{'project':'Other'},{'environment':None}]:
   with self.assertRaises(ValueError):m.validate_request({**self.args,**overrides},self.home)
 def test_missing_manifest_does_not_pick_available_prod_key(self):
  (self.repo/'keydesk.project.json').unlink();p=self.home/'.config/keydesk/mcp-connections.json';p.parent.mkdir(parents=True);p.write_text(json.dumps([{'project':'Other','environment':'prod','knownBindings':{'TOKEN':'value'}}]))
  self.assertEqual(m.resolve(str(self.repo),home=self.home)['state'],'unconfigured')
 def test_signed_cli_gets_names_and_exact_body_only_and_temp_cleanup(self):
  cli=self.home/'.local/bin/keydesk';cli.parent.mkdir(parents=True);cli.touch();saved=[]
  def runner(argv,**kw):
   self.assertEqual(argv[:8],[str(cli),'request','--project','Example','--env','dev','--key','TOKEN'])
   p=pathlib.Path(argv[-1]);saved.append(p);self.assertEqual(p.read_text(),self.args['body']);self.assertEqual(p.stat().st_mode & 0o777,0o600)
   return subprocess.CompletedProcess(argv,0,json.dumps({'status':200,'approval':'reused','credentialDelivery':'broker_only','body':'{}'}),'')
  result=m.execute(self.args,runner,self.home);self.assertEqual(result['approval'],'reused');self.assertFalse(saved[0].exists())
 def test_invalid_context_never_starts_cli(self):
  runner=Mock()
  with self.assertRaises(ValueError):m.execute({**self.args,'key':'MISSING'},runner,self.home)
  runner.assert_not_called()
 def test_approval_failure_is_not_retried(self):
  cli=self.home/'.local/bin/keydesk';cli.parent.mkdir(parents=True);cli.touch()
  runner=Mock(return_value=subprocess.CompletedProcess([],1,'','approval denied'))
  result=m.execute(self.args,runner,self.home)
  self.assertEqual(result['error'],'keydesk_request_not_completed');self.assertEqual(runner.call_count,1)
 def test_http_error_retains_broker_status_without_retry(self):
  cli=self.home/'.local/bin/keydesk';cli.parent.mkdir(parents=True);cli.touch()
  runner=Mock(return_value=subprocess.CompletedProcess([],2,json.dumps({'status':429,'approval':'reused','credentialDelivery':'broker_only','body':'{}'}),''))
  result=m.execute(self.args,runner,self.home)
  self.assertEqual(result['status'],429);self.assertEqual(runner.call_count,1)
 def test_refuses_symlink_manifest_and_relative_repository(self):
  p=self.repo/'keydesk.project.json';p.rename(self.repo/'original');p.symlink_to(self.repo/'original')
  for repo in [str(self.repo),'Example']:
   with self.assertRaises(ValueError):m.resolve(repo,home=self.home)
 def test_protocol_discovery_and_context_use_no_vault(self):
  messages=[{'jsonrpc':'2.0','id':1,'method':'initialize','params':{}},{'jsonrpc':'2.0','method':'notifications/initialized'},{'jsonrpc':'2.0','id':2,'method':'tools/list','params':{}},{'jsonrpc':'2.0','id':3,'method':'tools/call','params':{'name':'project_context','arguments':{'repository':str(self.repo)}}}]
  p=subprocess.run(['python3',str(pathlib.Path(m.__file__))],input='\n'.join(json.dumps(x) for x in messages)+'\n',capture_output=True,text=True,timeout=5)
  responses=[json.loads(l) for l in p.stdout.splitlines()];self.assertEqual(p.returncode,0);self.assertEqual(responses[-1]['result']['structuredContent']['project'],'Example')
  self.assertEqual([t['name'] for t in responses[1]['result']['tools']],['project_context','request_http'])
unittest.main()
