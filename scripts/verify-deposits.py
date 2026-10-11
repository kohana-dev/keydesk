#!/usr/bin/env python3
"""Exercise the real signed app/CLI with only disposable fixture keys and an isolated socket."""
import json, os, pathlib, subprocess, tempfile, time, datetime
root = pathlib.Path(__file__).resolve().parent.parent
app = root / 'dist/Keydesk.app/Contents/MacOS/Keydesk'
cli = root / 'dist/Keydesk.app/Contents/Helpers/keydesk'
with tempfile.TemporaryDirectory(prefix='keydesk-deposit-qa-') as folder:
    socket_path = pathlib.Path(folder)/'cli.sock'
    process = subprocess.Popen([str(app), '--demo', '--demo-socket', str(socket_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline=time.monotonic()+10
        while not socket_path.exists():
            if process.poll() is not None or time.monotonic()>deadline: raise RuntimeError('Demo app startup failed')
            time.sleep(.1)
        environment = dict(os.environ, KEYDESK_SOCKET_PATH=str(socket_path))
        def call(args, data=None):
            result=subprocess.run([str(cli)]+args, input=data, capture_output=True, env=environment, timeout=10)
            text=(result.stdout+result.stderr).decode()
            assert 'DISPOSABLE_CLI_SENTINEL' not in text and 'DISPOSABLE_ENV_SENTINEL' not in text, 'Secret appeared in output'
            return result.returncode, text
        args=['store','--project','CLI Fixture','--env','dev','--name','CLI_DEMO_KEY','--stdin']
        code,text=call(args,b'DISPOSABLE_CLI_SENTINEL\n');assert code==0 and 'stored' in text
        code,_=call(args,b'DISPOSABLE_CLI_SENTINEL\n');assert code==1, 'Duplicate overwrote existing key'
        env_file=pathlib.Path(folder)/'.env';env_file.write_text('ENV_DEMO_KEY=DISPOSABLE_ENV_SENTINEL\n')
        code,text=call(['store','--project','CLI Fixture','--env','dev','--name','ENV_DEMO_KEY','--from-env-file',str(env_file)]);assert code==0 and 'stored' in text
        code,_=call(['delete-project','--project','CLI Fixture']);assert code==1, 'Deletion requires explicit exclusive-key flag'
        code,text=call(['delete-project','--project','CLI Fixture','--delete-exclusive-keys']);assert code==0
        deletion=json.loads(text);assert deletion['projectsRemoved']==1 and deletion['exclusiveCredentialsRemoved']==2 and deletion['unrelatedDataPreserved']
        code,_=call(['lock']);assert code==0
        code,_=call(['delete-project','--project','CLI Fixture','--delete-exclusive-keys']);assert code==1, 'Locked deletion must fail'
        code,text=call(['store','--project','CLI Fixture','--env','dev','--name','LOCKED_DEMO_KEY','--stdin'],b'DISPOSABLE_CLI_SENTINEL\n');assert code==0 and 'queued' in text
        code,_=call(['run','--project','CLI Fixture','--env','dev','--only','CLI_DEMO_KEY','--','/usr/bin/true']);assert code==1
        report={'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'mode':'isolated signed demo app and bundled CLI','stdin_store_pass':True,'env_file_store_pass':True,'duplicate_store_rejected':True,'locked_store_queued_without_authentication':True,'locked_run_rejected':True,'no_values_in_cli_output':True,'real_vault_used':False,'project_deletion_verified':True,'project_deletion_explicit_flag_required':True,'locked_project_deletion_rejected':True}
        (root/'artifacts/deposit-cli-verification.json').write_text(json.dumps(report,indent=2)+'\n')
        print('SIGNED_APP_CLI_STORE_LOCKED_QUEUE_DUPLICATE_REJECTION_PASS')
    finally:
        process.terminate()
        try:process.wait(timeout=5)
        except subprocess.TimeoutExpired:process.kill();process.wait(timeout=5)
