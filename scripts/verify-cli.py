#!/usr/bin/env python3
import os, pty, subprocess, select, time, termios, signal, pathlib, json
exe=str(pathlib.Path('dist/bin/keydesk').resolve());env={**os.environ,'KEYDESK_SOCKET_PATH':'/tmp/keydesk-v021-qa/cli.sock'}
base=[exe,'run','--project','Studio Notes','--env','dev','--only','OPENAI_API_KEY']
results={}
def read_until(master,process,needle,timeout=90):
    data=b'';deadline=time.monotonic()+timeout
    while time.monotonic()<deadline:
        if select.select([master],[],[],.1)[0]:
            try: chunk=os.read(master,4096)
            except OSError:break
            data+=chunk
            if needle in data:return data
        if process.poll() is not None:break
    raise AssertionError('terminal output timeout: '+repr(data)+' exit='+str(process.poll())+' stderr='+repr(process.stderr.read() if process.poll() is not None else b'running'))
master,slave=pty.openpty();before=termios.tcgetattr(slave)
p=subprocess.Popen(base+['--interactive','--','/bin/sh','-c',"test -z \"$RESEND_API_KEY\" || exit 91; test -t 0 || exit 92; printf 'PROMPT: '; read reply; printf '%s:%s\\n' \"$reply\" \"$OPENAI_API_KEY\"; exit 7"],stdin=slave,stdout=slave,stderr=subprocess.PIPE,env=env)
print('WAIT_FOR_INTERACTIVE_APPROVAL',flush=True)
data=read_until(master,p,b'PROMPT: ');print('PROMPT_RECEIVED',flush=True);os.write(master,b'hello\n');data+=read_until(master,p,b'[REDACTED]')
p.wait(timeout=5)
assert p.returncode==7 and b'DEMO_ONLY_' not in data and termios.tcgetattr(slave)==before
results['interactive_TTY_selected_variables_redacted_exit7_terminal_restored']=True
os.close(master);os.close(slave)
master,slave=pty.openpty();before=termios.tcgetattr(slave)
p=subprocess.Popen(base+['--interactive','--','/bin/sh','-c',"printf 'STARTED\\n'; sleep 30"],stdin=slave,stdout=slave,stderr=subprocess.PIPE,env=env)
print('WAIT_FOR_SIGTERM_APPROVAL',flush=True)
read_until(master,p,b'STARTED');assert termios.tcgetattr(slave)!=before
p.send_signal(signal.SIGTERM);p.wait(timeout=5)
assert p.returncode==143 and termios.tcgetattr(slave)==before
results['external_SIGTERM_terminal_restored_exit143']=True
os.close(master);os.close(slave)
p=subprocess.Popen(base+['--keep-running','--','/bin/sh','-c',"printf 'RUNNING\\n'; sleep 10; printf 'DONE:%s\\n' \"$OPENAI_API_KEY\""],stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env)
print('WAIT_FOR_KEEP_RUNNING_APPROVAL',flush=True)
assert p.stdout.readline()==b'RUNNING\n'
print('WAIT_FOR_APP_LOCK',flush=True)
output,error=p.communicate(timeout=15)
assert p.returncode==0 and b'DONE:[REDACTED]' in output and b'DEMO_ONLY_' not in output
results['explicit_keep_running_survives_app_lock']=True
pathlib.Path('artifacts/cli-verification-v0.2.json').write_text(json.dumps(results,indent=2))
print('CLI_INTERACTIVE_SIGNALS_KEEP_RUNNING_PASS',flush=True)
