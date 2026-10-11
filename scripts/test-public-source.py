#!/usr/bin/env python3
import importlib.util,pathlib,tempfile,unittest,json
spec=importlib.util.spec_from_file_location('exporter',pathlib.Path(__file__).with_name('export-public-source.py'));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class ExportTests(unittest.TestCase):
 def test_sensitive_content_rejected_without_value_in_error(self):
  with tempfile.TemporaryDirectory() as t:
   f=pathlib.Path(t)/'fixture.txt'
   for value in ['/'+'Users/'+'privateuser/example','-----BEGIN '+'PRIVATE KEY-----','AKIA'+'A'*16]:
    f.write_text(value)
    with self.assertRaises(ValueError) as result:m.scan(pathlib.Path(t))
    self.assertNotIn(value,str(result.exception))
 def test_clean_export_omits_local_history_evidence_and_unreviewed_artwork(self):
  with tempfile.TemporaryDirectory() as t:
   report=m.export(t);tree=pathlib.Path(t)/'Keydesk-source'
   self.assertFalse((tree/'.git').exists());self.assertFalse((tree/'artifacts').exists())
   providers={x['provider'] for x in json.loads((tree/'Resources/ProviderLogos/manifest.json').read_text())}
   self.assertNotIn('Postmark',providers);self.assertNotIn('Amplitude',providers)
   self.assertTrue(report['scan_passed']);self.assertEqual(len(providers),55)
if __name__=='__main__':unittest.main()
