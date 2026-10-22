# drive-autosleep-zimaos

Spins down idle HDDs on ZimaOS (tested on an HP ProDesk G4, i5-8500) to reach <15W idle power.
A small container watches `/sys/block/<dev>/stat` and puts a drive into standby with `smartctl` after it has been idle for a configurable time. Drives that are already asleep are never woken by the check.

## How it works

Every `CHECK_INTERVAL` seconds, for each drive in `DRIVES`:

1. If the drive is already in standby (`smartctl -n standby`), do nothing.
2. Otherwise compare `/sys/block/<dev>/stat` with the previous reading. If unchanged, the idle counter goes up; if changed, it resets.
3. When the idle time reaches `IDLE_MINUTES`, run `smartctl -s standby,now` (falling back to `hdparm -y`).

## Requirements

- ZimaOS (or CasaOS) with Docker and SSH access
- One or more spinning HDDs (SSDs do not need this)
- Internet access on first start (the container installs `smartmontools` and `hdparm` from Alpine)

## Installation

### 1. Find your drive names

SSH into the ZimaOS host and list the disks:

```bash
lsblk -o NAME,SIZE,ROTA,MOUNTPOINT
```

`ROTA=1` marks spinning disks. Note their names (e.g. `sda`, `sdb`). Do not include your system SSD.

### 2. Get the files

```bash
cd /DATA
sudo git clone https://github.com/bilinskiad/drive-autosleep-zimaos.git
```

If `git` is not available, download the two files instead:

```bash
sudo mkdir -p /DATA/drive-autosleep-zimaos && cd /DATA/drive-autosleep-zimaos
sudo curl -fLO https://raw.githubusercontent.com/bilinskiad/drive-autosleep-zimaos/main/autosleep_both_drives.sh
sudo curl -fLO https://raw.githubusercontent.com/bilinskiad/drive-autosleep-zimaos/main/docker-compose.yml
```

### 3. Put the script where the container expects it

The compose file mounts `/DATA/autosleep_both_drives.sh`:

```bash
sudo cp /DATA/drive-autosleep-zimaos/autosleep_both_drives.sh /DATA/autosleep_both_drives.sh
```

(Or edit the volume path in `docker-compose.yml` to point at the cloned copy.)

### 4. Configure

Edit `docker-compose.yml` and set the environment values:

```yaml
environment:
  DRIVES: "sda sdb"      # space-separated, no /dev/ prefix
  IDLE_MINUTES: "10"
  CHECK_INTERVAL: "60"
```

| Variable | Default | Meaning |
|---|---|---|
| `DRIVES` | `sda sdb` | Block devices to manage |
| `IDLE_MINUTES` | `10` | Idle time before standby |
| `CHECK_INTERVAL` | `60` | Seconds between checks |

### 5. Start

```bash
cd /DATA/drive-autosleep-zimaos
sudo docker compose up -d
```

The container uses `restart: unless-stopped`, so it comes back after a reboot.

**Alternative (ZimaOS web UI):** App Store, Custom Install, Docker Compose, then paste the contents of `docker-compose.yml`.

### 6. Verify

```bash
sudo docker logs --tail 20 drive-autosleep
```

You should see `Starting autosleep: drives='sda sdb' ...`. After the idle time passes, a line like `sda: idle for 10m, entering standby` appears.

Check the drive state without waking it:

```bash
sudo smartctl -n standby /dev/sda
```

Expected output: `Device is in Standby mode`.

To test immediately:

```bash
sudo smartctl -s standby,now /dev/sda
```

## Updating

```bash
cd /DATA/drive-autosleep-zimaos && sudo git pull
sudo cp autosleep_both_drives.sh /DATA/autosleep_both_drives.sh
sudo docker restart drive-autosleep
```

## Uninstalling

```bash
cd /DATA/drive-autosleep-zimaos && sudo docker compose down
```

## Troubleshooting

**The drive keeps waking up.** Something is writing to it. Containers storing configs, SQLite databases or logs on the HDD are the usual cause. Keep app `/config` folders on the SSD (`/DATA/AppData`) and only media and downloads on the HDD. Find the mounts with:

```bash
sudo docker ps -q | while read id; do sudo docker inspect "$id" --format 'Container: {{.Name}}{{"\n"}}{{range .Mounts}}  Host Path: {{.Source}} -> Container Path: {{.Destination}}{{"\n"}}{{end}}'; done
```

Anything under `/media/HDD_Data1` that is not media is a candidate to move. The full migration walkthrough is in [docs/troubleshooting-log.md](docs/troubleshooting-log.md).

**`sda: not present, skipping` in the logs.** The name in `DRIVES` does not match a device. Re-check with `lsblk`. Device names can change between boots, so verify after hardware changes.

**`failed to enter standby`.** Some USB bridges and drives do not support standby commands. Try `sudo hdparm -y /dev/sda` on the host to confirm.

**Container exits immediately.** Check `sudo docker logs drive-autosleep`. A failed `apk add` means no internet access at start.

**ZimaOS has a read-only root filesystem and no `xargs`.** That is why the commands here use `while read` loops and keep files under `/DATA`.

