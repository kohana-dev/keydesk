#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import tempfile
import subprocess
import os
import sys
import unittest
from unittest.mock import patch
spec = importlib.util.spec_from_file_location('project_cli', Path(__file__).with_name('keydesk-project.py'))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

class ProjectCLI(unittest.TestCase):
    def setUp(self):
        self.config = {'version': 1, 'project': 'Example App', 'bindings': {'prod': {'GOOGLE_APPLICATION_CREDENTIALS': 'file', 'TOKEN': 'value'}, 'dev': {'DEMO_PATH': 'file'}}}
    def test_nearest_parent_and_safe_describe(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); (root/'nested').mkdir()
            (root/m.CONFIG_NAME).write_text(json.dumps(self.config))
            found, config = m.load_config(root/'nested')
            self.assertEqual(found, root.resolve()); self.assertEqual(config, self.config)
    def test_explicit_selection_and_literal_arguments(self):
        args = m.run_arguments(self.config, 'prod', 'TOKEN', 'GOOGLE_APPLICATION_CREDENTIALS', ['--', 'python3', 'a b.py', '$(no-shell)'])
        self.assertEqual(args, ['run','--project','Example App','--env','prod','--only','TOKEN','--files','GOOGLE_APPLICATION_CREDENTIALS','--','python3','a b.py','$(no-shell)'])
    def test_cross_environment_wrong_type_and_empty_rejected(self):
        for env, only, files in [('dev',None,'GOOGLE_APPLICATION_CREDENTIALS'),('prod','GOOGLE_APPLICATION_CREDENTIALS',None),('prod',None,'TOKEN'),('prod',None,None),('prod',None,'GOOGLE_APPLICATION_CREDENTIALS,GOOGLE_APPLICATION_CREDENTIALS')]:
            with self.assertRaises(ValueError): m.run_arguments(self.config,env,only,files,['true'])
    def test_document_fields_forwarded_without_reading_values(self):
        self.config['bindings']['prod'].update({'DOCUMENT':'json','FIELDS':'keyValue'})
        selectors=['AUTH_TOKEN=DOCUMENT#/services/0/token','REGION=FIELDS#/a~1b/~0name','ROOT=DOCUMENT#']
        args=m.run_arguments(self.config,'prod','TOKEN','GOOGLE_APPLICATION_CREDENTIALS',['--','tool','$(literal)'],selectors,'AUTH_TOKEN')
        self.assertEqual(args,['run','--project','Example App','--env','prod','--only','TOKEN','--files','GOOGLE_APPLICATION_CREDENTIALS','--select',selectors[0],'--select',selectors[1],'--select',selectors[2],'--stdin-key','AUTH_TOKEN','--','tool','$(literal)'])
        self.assertEqual(args.count('--select'),3)
    def test_document_selectors_accept_legacy_metadata_but_reject_wrong_sources_and_collisions(self):
        self.config['bindings']['prod'].update({'DOCUMENT':'json','FIELDS':'keyValue','NOTE':'text','API':'apiKey'})
        self.assertIn('CHILD=TOKEN#/known',m.run_arguments(self.config,'prod',None,None,['true'],['CHILD=TOKEN#/known']))
        for selectors in [['TOKEN=DOCUMENT#/a'],['GOOGLE_APPLICATION_CREDENTIALS=DOCUMENT#/a'],['DUP=DOCUMENT#/a','DUP=FIELDS#/b'],['OUT=NOTE#/a'],['OUT=API#/a'],['OUT=GOOGLE_APPLICATION_CREDENTIALS#/a'],['OUT=MISSING#/a'],['PATH=DOCUMENT#/a'],['ld_preload=DOCUMENT#/a'],['BAD-NAME=DOCUMENT#/a'],['OUT=DOCUMENT#bad'],['OUT=DOCUMENT#/~2'],['OUT=DOCUMENT#/'+('x'*2048)],['OUT=DOCUMENT#'+'/x'*65]]:
            with self.assertRaises(ValueError):m.run_arguments(self.config,'prod','TOKEN','GOOGLE_APPLICATION_CREDENTIALS',['true'],selectors)
        for stdin in ['MISSING','GOOGLE_APPLICATION_CREDENTIALS']:
            with self.assertRaises(ValueError):m.run_arguments(self.config,'prod',None,'GOOGLE_APPLICATION_CREDENTIALS',['true'],['OUT=DOCUMENT#/a'],stdin)
    def test_new_binding_kinds_are_names_only_and_invalid_types_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/m.CONFIG_NAME
            kinds=['value','apiKey','keyValue','json','text','file']
            self.config['bindings']['dev']={f'ITEM_{i}':kind for i,kind in enumerate(kinds)}
            path.write_text(json.dumps(self.config))
            self.assertEqual(m.load_config(d)[1]['bindings']['dev'],self.config['bindings']['dev'])
            self.config['bindings']['dev']['BAD']='unknown'
            path.write_text(json.dumps(self.config))
            with self.assertRaises(ValueError):m.load_config(d)
    def test_imports_filters_unexpected_fields_and_needs_no_vault(self):
        with tempfile.TemporaryDirectory() as d:
            registry=Path(d)/'.config/keydesk/imported-files.json'; registry.parent.mkdir(parents=True)
            registry.write_text(json.dumps([{'project':'Example','environment':'dev','variable':'FILE_PATH','kind':'file','state':'stored','value':'NEVER_RETURN_THIS_VALUE','source':'/private/source'}]))
            result=subprocess.run([sys.executable,str(Path(__file__).with_name('keydesk-project.py')),'imports'],env={**os.environ,'HOME':d},capture_output=True,text=True)
            self.assertEqual(result.returncode,0)
            self.assertNotIn('NEVER_RETURN_THIS_VALUE',result.stdout)
            self.assertNotIn('/private/source',result.stdout)
            self.assertEqual(json.loads(result.stdout)[0]['variable'],'FILE_PATH')
    def test_symlink_config_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); (root/'original').write_text(json.dumps(self.config)); (root/m.CONFIG_NAME).symlink_to(root/'original')
            with self.assertRaises(ValueError): m.load_config(root)
    def test_request_preserves_literal_url_and_does_not_read_body(self):
        with tempfile.TemporaryDirectory() as d:
            cli = Path(d)/'.local/bin/keydesk'; cli.parent.mkdir(parents=True); cli.touch()
            argv = ['keydesk-project', 'request', '--env', 'prod', '--key', 'TOKEN', '--method', 'POST', '--url', 'https://api.cloudflare.com/x?q=$(no-shell)', '--body-file', 'not-read.json']
            with patch.object(sys, 'argv', argv), patch.object(m.Path, 'home', return_value=Path(d)), patch.object(m, 'load_config', return_value=(Path(d),self.config)), patch.object(m.subprocess, 'call', return_value=0) as call:
                self.assertEqual(m.main(), 0)
                args = call.call_args.args[0]
                self.assertEqual(args[:12], [str(cli),'request','--project','Example App','--env','prod','--key','TOKEN','--method','POST','--url','https://api.cloudflare.com/x?q=$(no-shell)'])
                self.assertEqual(args[12:], ['--body-file',str(Path('not-read.json').absolute())])
    def test_request_rejects_file_and_multiple_key_selection(self):
        for key in ['GOOGLE_APPLICATION_CREDENTIALS','TOKEN,TOKEN','MISSING']:
            with patch.object(sys, 'argv', ['keydesk-project','request','--env','prod','--key',key,'--url','https://api.cloudflare.com/']), patch.object(m, 'load_config', return_value=(Path('/tmp'),self.config)), patch.object(m.subprocess, 'call') as call:
                self.assertEqual(m.main(), 2)
                call.assert_not_called()
    def test_request_document_field_and_provider_forward_exact_empty_root(self):
        self.config['bindings']['prod']['CONFIG']='json'
        with tempfile.TemporaryDirectory() as d:
            cli=Path(d)/'.local/bin/keydesk';cli.parent.mkdir(parents=True);cli.touch()
            argv=['keydesk-project','request','--env','prod','--key','CONFIG','--field','','--provider','OpenAI','--url','https://api.openai.com/v1/models']
            with patch.object(sys,'argv',argv),patch.object(m.Path,'home',return_value=Path(d)),patch.object(m,'load_config',return_value=(Path(d),self.config)),patch.object(m.subprocess,'call',return_value=0) as call:
                self.assertEqual(m.main(),0)
                self.assertEqual(call.call_args.args[0][-4:],['--field','','--provider','OpenAI'])
    def test_request_invalid_document_arguments_never_start_helper(self):
        self.config['bindings']['prod'].update({'CONFIG':'json','NOTE':'text'})
        for extra in [['--key','CONFIG'],['--key','NOTE','--field','/a'],['--key','TOKEN','--provider','OpenAI'],['--key','CONFIG','--field','/~bad']]:
            with patch.object(sys,'argv',['keydesk-project','request','--env','prod','--url','https://api.openai.com/v1/models',*extra]),patch.object(m,'load_config',return_value=(Path('/tmp'),self.config)),patch.object(m.subprocess,'call') as call:
                self.assertEqual(m.main(),2);call.assert_not_called()
    def test_weather_document_requests_forward_only_provider_and_public_target(self):
        self.config['bindings']['prod']['WEATHER_CONFIG']='json'
        targets={
            'OpenWeather':'https://api.openweathermap.org/data/2.5/weather?lat=37.5665&lon=126.9780&units=metric',
            'WeatherAPI':'https://api.weatherapi.com/v1/current.json?q=Seoul',
            'Tomorrow.io':'https://api.tomorrow.io/v4/weather/realtime?location=Seoul',
            'Visual Crossing':'https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline/Seoul?contentType=json',
            'Weatherbit':'https://api.weatherbit.io/v2.0/current?city=Seoul',
            'AccuWeather':'https://dataservice.accuweather.com/locations/v1/cities/search?q=Seoul',
        }
        with tempfile.TemporaryDirectory() as d:
            cli=Path(d)/'.local/bin/keydesk';cli.parent.mkdir(parents=True);cli.touch()
            for provider,url in targets.items():
                with self.subTest(provider=provider):
                    argv=['keydesk-project','request','--env','prod','--key','WEATHER_CONFIG','--field','/token','--provider',provider,'--url',url]
                    with patch.object(sys,'argv',argv),patch.object(m.Path,'home',return_value=Path(d)),patch.object(m,'load_config',return_value=(Path(d),self.config)),patch.object(m.subprocess,'call',return_value=0) as call:
                        self.assertEqual(m.main(),0)
                        self.assertEqual(call.call_args.args[0],[str(cli),'request','--project','Example App','--env','prod','--key','WEATHER_CONFIG','--method','GET','--url',url,'--field','/token','--provider',provider])
                        self.assertEqual(call.call_count,1)

unittest.main()
