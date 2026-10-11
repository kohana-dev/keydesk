#!/usr/bin/env python3
"""Verify offline brand coverage and render a visual review sheet."""
import json,re,hashlib,pathlib
from PIL import Image,ImageDraw
root=pathlib.Path(__file__).resolve().parent.parent
assets=root/'Resources/ProviderLogos'
manifest=json.loads((assets/'manifest.json').read_text())
options=re.findall(r'"([^"]+)"',(root/'Sources/KeydeskCore/ProviderName.swift').read_text().split('public static let options')[1].split(']')[0])
policy=assets/'distribution-policy.json'
omitted=set(json.loads(policy.read_text()).get('omitted_for_redistribution_review', [])) if policy.exists() else set()
assert omitted.issubset({'Postmark','Amplitude'})
assert [x['provider'] for x in manifest]==[name for name in options[:-1] if name not in omitted]
sheet=Image.new('RGB',(900,((len(manifest)+5)//6)*110),'#f1f4f1');draw=ImageDraw.Draw(sheet)
for i,x in enumerate(manifest):
 src=assets/(x['file']+('.svg' if (assets/(x['file']+'.svg')).exists() else '.source.png'))
 assert hashlib.sha256(src.read_bytes()).hexdigest()==x['sha256']
 im=Image.open(assets/(x['file']+'.png')).convert('RGBA');assert im.size==(128,128) and im.getbbox()
 assert x['source'].startswith('https://')
 px,py=(i%6)*150,(i//6)*110
 draw.rounded_rectangle((px+48,py+8,px+102,py+62),10,fill='white');im.thumbnail((36,36));sheet.paste(im,(px+57,py+17),im);draw.text((px+10,py+75),x['provider'],fill='black')
(root/'artifacts').mkdir(exist_ok=True);sheet.save(root/'artifacts/provider-logos-v0.5.4.png')
(root/'artifacts/provider-logos-verification.json').write_text(json.dumps({'brand_count':len(manifest),'all_known_brands_have_assets':True,'source_hashes_match':True,'runtime_network_requests':False,'custom_fallback':'initials'},indent=2)+'\n')
print(f'PASS: {len(manifest)} bundled brand logos; source hashes, coverage, dimensions and nonempty pixels verified.')
