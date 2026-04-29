# kopia_hetzner

Idempotent setup and scheduled backup scripts for [Kopia](https://kopia.io/)
against a [Hetzner Storage Box](https://www.hetzner.com/storage/storage-box/)
over SFTP.

Designed to work with the quirks of Hetzner Storage Box and the limits of
Kopia's internal SSH client, while still being reasonably portable to any
SSH-accessible storage by tweaking the config.

## Why these scripts exist

Setting up Kopia on a Hetzner Storage Box correctly requires working around
several non-obvious issues. These scripts encode the workarounds:

- **Sub-account `.ssh/` does not exist by default** — `ssh-copy-id -s`
  may fail; the scripts fall back to an SFTP batch that creates `.ssh/` and
  appends the key idempotently.
- **Kopia's Go SSH `knownhosts` library** rejects valid host keys
  (`knownhosts: key mismatch`, [kopia#2948](https://github.com/kopia/kopia/issues/2948),
  [kopia#1777](https://github.com/kopia/kopia/issues/1777)). Workaround:
  `--external` to delegate the SSH handshake to the system `ssh` binary.
- **Kopia with `--external` does not reliably forward `--port` to `ssh`**,
  falling back to port 22. Hetzner Storage Box on port 22 only exposes RSA/DSS
  host keys (no ED25519). The scripts pass `-p $PORT` and `-o Port=$PORT`
  inside `--ssh-args` so the right port is used.
- **Hetzner publishes official host key fingerprints** — the scripts verify
  the result of `ssh-keyscan` against them to prevent MitM at first contact.
- **`mariadb-dump` vs `'root'@'localhost'`** — the optional pre-snapshot DB
  dump uses the *application* user (`MYSQL_USER`) rather than root, forces
  TCP to `127.0.0.1` to match `'<user>'@'%'`, and prefers the modern
  `mariadb-dump` binary while falling back to `mysqldump`.

## Files

| File                          | Purpose                                          |
| ----------------------------- | ------------------------------------------------ |
| `setup.sh`                    | One-shot, idempotent setup                       |
| `backup.sh`                   | Snapshot runner (called by cron / systemd timer) |
| `kopia_hetzner.conf.example`  | Configuration template                           |

## Quick start

```bash
# 1. Copy the example config and edit it
sudo install -m 600 kopia_hetzner.conf.example /etc/kopia_hetzner.conf
sudo $EDITOR /etc/kopia_hetzner.conf

# 2. Run the setup (you will be asked once for the SSH password and
#    once for the new repository encryption password). It will also ask
#    whether to install a systemd timer for scheduled backups.
sudo ./setup.sh -c /etc/kopia_hetzner.conf

# 3. Test a backup
sudo ./backup.sh -c /etc/kopia_hetzner.conf

# 4. (optional) Inspect kopia state
sudo kopia --config-file=/root/.config/kopia/<INSTANCE>/repository.config snapshot list
```

## Multiple instances on the same host

The scripts isolate state per `INSTANCE_NAME`:

- SSH key:           `/root/.ssh/kopia_<INSTANCE>_ed25519`
- known_hosts:       `/root/.ssh/kopia_<INSTANCE>_known_hosts`
- Kopia config dir:  `/root/.config/kopia/<INSTANCE>/`
- systemd unit base: `kopia-<INSTANCE>` (`.service` and `.timer`)
- Log file:          `/var/log/kopia-<INSTANCE>.log`

Just create another config file with a different `INSTANCE_NAME` and run
`setup.sh -c /path/to/other.conf`.

## Scheduling

`setup.sh` can install a systemd timer (preferred over cron):

- `Persistent=true`: catches up missed runs after downtime
- `RandomizedDelaySec`: jitter to avoid thundering herd
- Logs in `journalctl -u kopia-<INSTANCE>.service` and `/var/log/kopia-<INSTANCE>.log`

Default schedule: daily at 03:30 local time + up to 30 minutes of jitter.
Adjust `TIMER_ONCALENDAR` and `TIMER_RANDOMIZED_DELAY` in the config.

```bash
# install/enable
sudo ./setup.sh -c /etc/kopia_hetzner.conf --install-timer

# inspect
systemctl list-timers kopia-<INSTANCE>.timer
systemctl status kopia-<INSTANCE>.service
journalctl -u kopia-<INSTANCE>.service -n 200

# run on demand
sudo systemctl start kopia-<INSTANCE>.service
```

## Recovery

`setup.sh` is idempotent: re-run it after any interrupted setup.

```bash
# Restart from the first incomplete step
sudo ./setup.sh -c /etc/kopia_hetzner.conf

# Wipe local state only (key, known_hosts, password, kopia config, timer).
# The Storage Box is NOT touched.
sudo ./setup.sh -c /etc/kopia_hetzner.conf --reset

# If the remote repository got corrupted, delete it on the Storage Box and
# re-run setup:
sftp -i /root/.ssh/kopia_<INSTANCE>_ed25519 -P 23 <user>@<host>
sftp> rm -r kopia
sftp> bye
sudo ./setup.sh -c /etc/kopia_hetzner.conf
```

## Hetzner Storage Box limits worth knowing

- **Max 10 simultaneous SFTP connections** per (sub)account. The default
  `KOPIA_PARALLEL=4` stays comfortably under that.
- **SSH key formats**: port 23 wants OpenSSH one-line (default of
  `ssh-keygen`). Allowed algorithms: `ssh-ed25519`, `ssh-rsa`.
- Port 22 (legacy SCP/SFTP) only exposes RSA/DSS host keys; port 23
  (extended SSH) has ED25519. The scripts always use port 23.
- Sub-accounts need their `.ssh/` to be created via SFTP — handled
  automatically by `setup.sh`.
- You cannot create `/etc` or `/lib` paths on a Storage Box (irrelevant for
  Kopia; just don't set `SB_PATH=/etc/...`).
- Unlimited traffic, 1–10 Gbit/s shared host bandwidth.

## License

Same as the rest of [steccaScripts](../) (see top-level `LICENSE`).
