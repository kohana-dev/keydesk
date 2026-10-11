#!/usr/bin/env python3
import pathlib, tempfile, subprocess, time, json
probe = pathlib.Path('.build/release/KeydeskStorageProbe').resolve()
results = {}
with tempfile.TemporaryDirectory(prefix='keydesk-storage-qa-') as directory:
    root = pathlib.Path(directory); target = root / 'atomic-fixture.bin'
    old = b'O' * 1048576; new = b'N' * (32 * 1048576)
    # A nonzero probe exit alone cannot prove ENOSPC: first prove the fixture executes.
    baseline=subprocess.run([str(probe),'write',str(target)],capture_output=True,timeout=15)
    assert baseline.returncode == 0 and target.read_bytes() == new, 'Probe normal write did not complete'
    results['normal_write_complete']=True
    generations = []
    for delay in [.001,.003,.006,.01,.015,.02,.03,.04,.06,.1,.15,.2,.3,.5,.8]:
        target.write_bytes(old)
        process = subprocess.Popen([str(probe), 'write', str(target)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(delay)
        if process.poll() is None: process.kill()
        process.wait()
        actual = target.read_bytes()
        assert actual in (old, new), 'Incomplete committed generation'
        generations.append('old' if actual == old else 'new')
    results['SIGKILL_atomic_generation'] = generations
    image = root/'full.dmg'; mount = root/'mounted'; mount.mkdir()
    create = subprocess.run(['hdiutil','create','-size','16m','-fs','HFS+','-volname','Keydesk-QA','-ov',str(image)], capture_output=True)
    attach = subprocess.run(['hdiutil','attach','-nobrowse','-mountpoint',str(mount),str(image)], capture_output=True) if create.returncode == 0 else create
    if attach.returncode == 0:
        try:
            destination = mount/'atomic-fixture.bin'; destination.write_bytes(old)
            result = subprocess.run([str(probe),'write',str(destination)],capture_output=True)
            assert result.returncode != 0 and b'fixture_write_failed' in result.stderr and destination.read_bytes() == old
            assert not list(mount.glob('.keydesk-*.tmp'))
            results['real_ENOSPC_preserves_current'] = True
        finally:
            subprocess.run(['hdiutil','detach',str(mount)],check=True,capture_output=True)
    else: results['real_ENOSPC'] = {'blocked': attach.stderr.decode(errors='replace').strip()}
pathlib.Path('artifacts/storage-verification.json').write_text(json.dumps(results, indent=2))
print(json.dumps(results, indent=2))
