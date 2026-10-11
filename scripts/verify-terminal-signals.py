#!/usr/bin/env python3
# Disposable local protocol fixture; no vault, keys, app approvals, or network calls.
import socket, os, tempfile, pathlib, subprocess, pty, select, termios, signal, json
with tempfile.TemporaryDirectory(prefix='keydesk-signal-qa-') as root:
    path=str(pathlib.Path(root)/'fixture.sock'); listener=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);listener.bind(path);os.chmod(path,0o600);listener.listen(1);listener.settimeout(10)
    for iteration in range(10):
        master,slave=pty.openpty();before=termios.tcgetattr(slave)
        p=subprocess.Popen(['dist/bin/keydesk','run','--project','fixture','--interactive','--only','FIXTURE_KEY','--','/bin/true'],stdin=slave,stdout=slave,stderr=subprocess.DEVNULL,env={**os.environ,'KEYDESK_SOCKET_PATH':path})
        channel,_=listener.accept(); reader=channel.makefile('rb');json.loads(reader.readline())
        channel.sendall(b'{"kind":"started"}\n'+json.dumps({'kind':'stdout','data':'U1RBUlRFRAo='}).encode()+b'\n')
        assert select.select([master],[],[],5)[0];os.read(master,4096)
        assert termios.tcgetattr(slave)!=before
        p.send_signal(signal.SIGTERM if iteration%2==0 else signal.SIGHUP);p.wait(timeout=5)
        expected=143 if iteration%2==0 else 129
        assert p.returncode==expected and termios.tcgetattr(slave)==before,(iteration,p.returncode)
        channel.close();reader.close();os.close(master);os.close(slave)
    listener.close()
pathlib.Path('artifacts/terminal-signal-verification.json').write_text(json.dumps({'fixture_only':True,'SIGTERM_restored_exit143':5,'SIGHUP_restored_exit129':5,'passed':True},indent=2))
print('SIGTERM_AND_SIGHUP_TERMINAL_RESTORE_10_CASES_PASS')
