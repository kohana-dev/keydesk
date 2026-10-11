#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
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
    def test_symlink_config_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); (root/'original').write_text(json.dumps(self.config)); (root/m.CONFIG_NAME).symlink_to(root/'original')
            with self.assertRaises(ValueError): m.load_config(root)

unittest.main()
