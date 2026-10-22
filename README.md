# drive-autosleep-zimaos

Spins down idle HDDs on ZimaOS (tested on an HP ProDesk G4, i5-8500) to reach <15W idle power.
A small container watches `/sys/block/<dev>/stat` and puts a drive into standby with `smartctl` after it has been idle for a configurable time. Drives already asleep are never woken by the check.

## Usage

1. Copy `autosleep_both_drives.sh` to `/DATA/autosleep_both_drives.sh` on the ZimaOS host.
2. Edit `DRIVES` in `docker-compose.yml` (e.g. `"sda sdb"`).
3. `sudo docker compose up -d`

| Variable | Default | Meaning |
|---|---|---|
| `DRIVES` | `sda sdb` | Space-separated block devices |
| `IDLE_MINUTES` | `10` | Idle time before standby |
| `CHECK_INTERVAL` | `60` | Seconds between checks |

## Verify

```bash
sudo docker logs --tail 20 drive-autosleep
sudo smartctl -s standby,now /dev/sda   # manual standby
sudo smartctl -n standby /dev/sda       # reports state without waking the drive
```

## Important: keep containers off the HDD

Drives will not stay asleep if containers keep writing configs, SQLite DBs or logs to them. Keep app `/config` directories on the SSD (`/DATA/AppData`) and only media/downloads on the HDD. See [docs/troubleshooting-log.md](docs/troubleshooting-log.md) for the full migration walkthrough.
