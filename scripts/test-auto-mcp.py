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
 def test_document_fields_require_known_binding_and_valid_selector(self):
  self.config['bindings']['dev'].update({'CONFIG':'json','FIELDS':'keyValue','NOTE':'text','API':'apiKey'})
  (self.repo/'keydesk.project.json').write_text(json.dumps(self.config))
  for key,field in [('CONFIG','/auth/token'),('FIELDS','/a~1b/~0name'),('TOKEN',''),('CONFIG','/hash#name')]:
   context=m.validate_request({**self.args,'key':key,'field':field,'provider':'OpenAI'},self.home)
   self.assertEqual(context['project'],'Example')
  for overrides in [{'key':'CONFIG'},{'key':'NOTE','field':'/a'},{'key':'API','field':'/a'},{'field':None},{'field':'/~2'},{'field':'not/pointer'},{'field':'/'+'a'*2048},{'field':'/a'*65},{'provider':'OpenAI'},{'field':'/a','provider':'Other'},{'field':'/a','provider':None},{'field':'/a','unknown':'x'}]:
   with self.assertRaises(ValueError):m.validate_request({**self.args,**overrides},self.home)
 def test_document_request_forwards_only_pointer_and_provider_once(self):
  self.config['bindings']['dev']['CONFIG']='json';(self.repo/'keydesk.project.json').write_text(json.dumps(self.config))
  cli=self.home/'.local/bin/keydesk';cli.parent.mkdir(parents=True);cli.touch()
  args={k:v for k,v in self.args.items() if k!='body'};args.update(key='CONFIG',field='',provider='OpenAI')
  runner=Mock(return_value=subprocess.CompletedProcess([],0,json.dumps({'status':200,'credentialDelivery':'broker_only','body':'{}'}),''))
  m.execute(args,runner,self.home)
  argv=runner.call_args.args[0]
  self.assertEqual(argv[-4:],['--field','','--provider','OpenAI']);self.assertEqual(runner.call_count,1)
  self.assertNotIn('--body-file',argv)
 def test_context_returns_document_kinds_without_field_enumeration(self):
  self.config['bindings']['dev'].update({'CONFIG':'json','FIELDS':'keyValue','NOTE':'text','API':'apiKey'})
  (self.repo/'keydesk.project.json').write_text(json.dumps(self.config))
  result=m.resolve(str(self.repo),home=self.home)
  self.assertEqual(result['bindings'],self.config['bindings'])
  self.assertNotIn('fields',result);self.assertNotIn('contents',result)
 def test_weather_document_providers_forward_names_and_public_target_only(self):
  self.config['bindings']['dev']['WEATHER_CONFIG']='json';(self.repo/'keydesk.project.json').write_text(json.dumps(self.config))
  cli=self.home/'.local/bin/keydesk';cli.parent.mkdir(parents=True);cli.touch()
  targets={
   'OpenWeather':'https://api.openweathermap.org/data/2.5/weather?lat=37.5665&lon=126.9780',
   'WeatherAPI':'https://api.weatherapi.com/v1/current.json?q=Seoul',
   'Tomorrow.io':'https://api.tomorrow.io/v4/weather/realtime?location=Seoul',
   'Visual Crossing':'https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline/Seoul?contentType=json',
   'Weatherbit':'https://api.weatherbit.io/v2.0/current?city=Seoul',
   'AccuWeather':'https://dataservice.accuweather.com/locations/v1/cities/search?q=Seoul',
  }
  for provider,url in targets.items():
   with self.subTest(provider=provider):
    args={'repository':str(self.repo),'environment':'dev','key':'WEATHER_CONFIG','field':'/token','provider':provider,'method':'GET','url':url}
    runner=Mock(return_value=subprocess.CompletedProcess([],0,json.dumps({'status':200,'credentialDelivery':'broker_only','body':'{}'}),''))
    self.assertEqual(m.execute(args,runner,self.home)['status'],200)
    self.assertEqual(runner.call_args.args[0],[str(cli),'request','--project','Example','--env','dev','--key','WEATHER_CONFIG','--method','GET','--url',url,'--field','/token','--provider',provider])
    self.assertEqual(runner.call_count,1)
  with self.assertRaises(ValueError):m.validate_request({**args,'provider':'OpenWheater'},self.home)
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
  weather={'OpenWeather','WeatherAPI','Tomorrow.io','Visual Crossing','Weatherbit','AccuWeather'}
  self.assertTrue(weather.issubset(responses[1]['result']['tools'][1]['inputSchema']['properties']['provider']['enum']))
  self.assertEqual(responses[0]['result']['serverInfo']['version'],'0.7.21-project-router-1')
unittest.main()
