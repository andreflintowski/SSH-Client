"""Disposable loopback-only SSH/PTY fixture, with its own keys and credentials."""
import asyncio, asyncssh, fcntl, json, os, pty, secrets, signal, struct, subprocess, sys, termios
from pathlib import Path

root = Path(sys.argv[1])
if root.exists() and any(root.iterdir()):
    raise SystemExit('Use a new empty directory for disposable SSH fixture data')
root.mkdir(parents=True, exist_ok=True, mode=0o700)
root.chmod(0o700)
host_key = asyncssh.generate_private_key('ssh-ed25519')
client_key = asyncssh.generate_private_key('ssh-ed25519')
(root/'host').write_bytes(host_key.export_private_key())
(root/'host.pub').write_bytes(host_key.export_public_key())
(root/'client').write_bytes(client_key.export_private_key())
(root/'client-encrypted').write_bytes(client_key.export_private_key(passphrase='audit-passphrase'))
password = secrets.token_urlsafe(18)

class Shell(asyncssh.SSHServerSession):
    def connection_made(self, chan):
        self.chan, self.proc, self.master, self.size = chan, None, None, (80,24,0,0)
    def pty_requested(self, term_type, term_size, term_modes):
        self.size, self.term_type = term_size, term_type
        return True
    def shell_requested(self): return True
    def session_started(self):
        self.master, slave = pty.openpty()
        self.resize()
        def setup():
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
        self.proc = subprocess.Popen(['/bin/bash','--noprofile','--norc','-i'], stdin=slave, stdout=slave, stderr=slave,
             preexec_fn=setup, cwd=str(root), env={'PATH':'/usr/bin:/bin','TERM':getattr(self,'term_type','xterm-256color'),'PS1':'AUDIT> ','LC_ALL':'en_US.UTF-8'})
        os.close(slave)
        asyncio.get_running_loop().add_reader(self.master, self.read)
        asyncio.create_task(self.wait())
    def resize(self):
        if self.master is not None:
            w,h,pw,ph = self.size
            fcntl.ioctl(self.master, termios.TIOCSWINSZ, struct.pack('HHHH',h,w,pw,ph))
    def terminal_size_changed(self,w,h,pw,ph):
        self.size=(w,h,pw,ph); self.resize()
    def data_received(self,data,datatype):
        if self.master is not None: os.write(self.master,data)
    def read(self):
        try:
            data=os.read(self.master,65536)
            if data: self.chan.write(data)
            else: self.cleanup()
        except OSError: self.cleanup()
    async def wait(self):
        status=await asyncio.get_running_loop().run_in_executor(None,self.proc.wait)
        self.cleanup(); self.chan.exit(status)
    def cleanup(self):
        if self.master is not None:
            asyncio.get_running_loop().remove_reader(self.master)
            os.close(self.master); self.master=None
    def connection_lost(self,exc):
        self.cleanup()
        if self.proc and self.proc.poll() is None:
            try: os.killpg(self.proc.pid,signal.SIGHUP)
            except ProcessLookupError: pass

class Server(asyncssh.SSHServer):
    def begin_auth(self,username): return True
    def password_auth_supported(self): return True
    def public_key_auth_supported(self): return True
    def validate_password(self,username,pw): return username=='audit' and secrets.compare_digest(pw,password)
    def validate_public_key(self,username,key): return username=='audit' and key==client_key.convert_to_public()
    def session_requested(self): return Shell()

async def main():
    server=await asyncssh.create_server(Server,'127.0.0.1',0,server_host_keys=[host_key],encoding=None)
    config={'hostname':'127.0.0.1','port':server.get_port(),'username':'audit','password':password,
      'fingerprint':host_key.get_fingerprint('sha256'),'client_key':str(root/'client'),
      'encrypted_key':str(root/'client-encrypted'),'passphrase':'audit-passphrase'}
    (root/'config.json').write_text(json.dumps(config,indent=2))
    for name in ['host', 'client', 'client-encrypted', 'config.json']:
        (root/name).chmod(0o600)
    print(json.dumps({k:v for k,v in config.items() if k not in ('password',)}),flush=True)
    await server.wait_closed()

asyncio.run(main())
