#!/usr/bin/env python3
"""Build a fresh allowlisted source tree, without local evidence or Git history."""
import argparse, hashlib, json, pathlib, re, shutil, tempfile, zipfile
ROOT=pathlib.Path(__file__).resolve().parent.parent
FILES=['Package.swift','README.md','LICENSE','SECURITY.md','CONTRIBUTING.md','THIRD_PARTY_NOTICES.md','Resources/AppIcon/Cellar.icns','Resources/AppIcon/Cellar-source.png','Resources/AppIcon/README.md','.gitignore','docs/open-source-building.md','docs/open-source-readiness.md','docs/project-cli.md','docs/mcp-setup.md','docs/local-api-broker.md','integrations/skills/keydesk/SKILL.md','.github/workflows/ci.yml']
DIRS=['Sources','Tests']
SCRIPTS=['keydesk-project.py','test-project-cli.py','build-app.sh','prepare-release.sh','notarize.sh','verify-profile.py','verify-release.py','test-release-tools.py','install-ai-skills.py','install-mcp.py','install-auto-mcp.py','keydesk-mcp.py','test-auto-mcp.py','test-mcp-setup.py','export-public-source.py','verify-provider-logos.py','test-public-source.py','verify-protocol.py','verify-terminal-signals.py','verify-cli.py','verify-deposits.py','verify-storage.py','verify-mcp.py','verify-ai-client.py']
EXCLUDED_BRANDS={'Postmark','Amplitude'}
PATTERNS=[re.compile(rb'/Users/[A-Za-z0-9_.-]+/'),re.compile(rb'[A-Za-z0-9._%+-]+@(?:gmail|icloud|outlook)\.com',re.I),re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),re.compile(rb'\bAKIA[0-9A-Z]{16}\b'),re.compile(rb'\bgh[pousr]_[A-Za-z0-9]{30,}\b')]
def scan(tree):
 bad=[]
 for f in tree.rglob('*'):
  if not f.is_file():continue
  rel=f.relative_to(tree)
  if f.is_symlink():bad.append(str(rel)+' symlink');continue
  data=f.read_bytes()
  if any(p.search(data) for p in PATTERNS):bad.append(str(rel)+' sensitive-pattern')
  if f.name.startswith('.env') or f.suffix in {'.p8','.p12','.provisionprofile','.mobileprovision','.keydesk','.keychain-db'}:bad.append(str(rel)+' prohibited-file')
 if bad:raise ValueError('Export rejected (values withheld): '+', '.join(bad))
def export(destination):
 destination=pathlib.Path(destination).resolve();destination.mkdir(parents=True,exist_ok=True)
 with tempfile.TemporaryDirectory(prefix='keydesk-public-stage-') as t:
  tree=pathlib.Path(t)/'Keydesk-source';tree.mkdir()
  paths=FILES+['scripts/'+s for s in dict.fromkeys(SCRIPTS)]
  paths += [str(f.relative_to(ROOT)) for d in DIRS for f in (ROOT/d).rglob('*') if f.is_file() and '__pycache__' not in f.parts]
  for rel in paths:
   src=ROOT/rel
   if src.is_symlink():raise ValueError('Source symlink rejected: '+rel)
   dst=tree/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
  assets=tree/'Resources/ProviderLogos';assets.mkdir(parents=True)
  manifest=json.loads((ROOT/'Resources/ProviderLogos/manifest.json').read_text());approved=[x for x in manifest if x['provider'] not in EXCLUDED_BRANDS]
  for x in approved:
   for source in (ROOT/'Resources/ProviderLogos').glob(x['file']+'.*'):
    if source.is_symlink():raise ValueError('Asset symlink rejected')
    shutil.copy2(source,assets/source.name)
  for f in (ROOT/'Resources/ProviderLogos').glob('*LICENSE*'):shutil.copy2(f,assets/f.name)
  (assets/'manifest.json').write_text(json.dumps(approved,indent=2)+'\n')
  (assets/'distribution-policy.json').write_text(json.dumps({'omitted_for_redistribution_review':sorted(EXCLUDED_BRANDS),'fallback':'text initials'},indent=2)+'\n')
  (assets/'README.md').write_text('56 reviewed-source brand assets; Postmark and Amplitude use text initials. See THIRD_PARTY_NOTICES.md. No network downloads at runtime.\n')
  scan(tree)
  hashes={str(f.relative_to(tree)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(tree.rglob('*')) if f.is_file()}
  final=destination/'Keydesk-source'
  if final.exists():shutil.rmtree(final)
  shutil.copytree(tree,final)
  archive=destination/'Keydesk-source.zip'
  with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
   for f in sorted(tree.rglob('*')):
    if f.is_file():z.write(f,'Keydesk-source/'+str(f.relative_to(tree)))
  report={'file_count':len(hashes),'sha256':hashes,'archive_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'git_history_included':False,'private_evidence_included':False,'omitted_brand_artwork':sorted(EXCLUDED_BRANDS),'scan_passed':True}
  (destination/'source-manifest.json').write_text(json.dumps(report,indent=2)+'\n')
  return report
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--output',default=str(ROOT/'dist/public-source'));a=p.parse_args();r=export(a.output);print(f'PUBLIC_SOURCE_EXPORT_PASS: {r["file_count"]} files, no Git history or private evidence')
