# Optional live SSH regression tests

The ordinary `flutter test` suite covers startup, storage failures and fingerprint compatibility. Live tests are skipped unless `SSH_AUDIT_CONFIG` names a disposable fixture config.

With Python `asyncssh` and `bcrypt` installed in an isolated venv, run:

```sh
python test/support/ssh_server.py /path/to/new-empty-fixture-directory
# In another shell:
SSH_AUDIT_CONFIG=/path/to/new-empty-fixture-directory/config.json flutter test --concurrency=1
```

The fixture listens only on 127.0.0.1 and generates its own keys and password. It opens isolated bash PTYs with no user startup files. Compare the shown fingerprint with `ssh-keygen -lf /path/to/new-empty-fixture-directory/host.pub`. Stop the fixture with Ctrl-C and remove its temporary directory after the tests. Never supply working server credentials or use system Remote Login.
