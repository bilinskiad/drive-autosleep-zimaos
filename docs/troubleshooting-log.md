# HP ProDesk G4 Idle Power Optimization & ZimaOS Docker Migration Log

## Overview
This document records the troubleshooting steps, container volume adjustments, and configuration checks undertaken to achieve an idle power draw of <15W on an HP ProDesk G4 (i5-8500) running ZimaOS.

---

## 1. Initial Diagnostic & Problem Identification
- **Goal:** Minimize idle power draw to below 15W.
- **Root Cause Identified:** Frequent HDD (`/dev/sda` mounted at `/media/HDD_Data1`) wake-ups were triggered by SQLite databases, logs, and configuration files of background Docker containers running Prowlarr, Radarr, qBittorrent, Jellyfin, and Tailscale.
- **Environment Constraints:** ZimaOS utilizes a read-only root filesystem and lacks standard utilities like `xargs`.

---

## 2. Inspecting Docker Container Mounts
To locate where containers were storing their persistent configuration and data files, the following safe single-line loop was executed:

```bash
sudo docker ps -q | while read id; do sudo docker inspect "$id" --format 'Container: {{.Name}}{{"\n"}}{{range .Mounts}}  Host Path: {{.Source}} -> Container Path: {{.Destination}}{{"\n"}}{{end}}'; done
```

### Initial Findings:
- `prowlarr`, `radarr`, `qbittorrent`, `jellyfin`, and `tailscale` had their `/config` or state directories mapped directly onto `/media/HDD_Data1` (the mechanical HDD).
- This constant background read/write activity prevented `smartctl` autosleep scripts from keeping `/dev/sda` in standby mode.

---

## 3. Migrating Container Configurations to SSD (`/DATA`)
To ensure zero background writes on the HDD, configuration directories were moved to the internal SSD (`/DATA/AppData` or `/media/ZimaOS-HD/AppData`), while heavy media files and downloads remained on `/media/HDD_Data1`.

### Step-by-Step Migration Applied:
1. **Radarr:**
   - Stopped container: `sudo docker stop radarr`
   - Copied config: `sudo cp -r /media/HDD_Data1/appdata/arrstack/radarr /DATA/AppData/radarr`
   - Updated ZimaOS UI mount path for `/config` to `/media/ZimaOS-HD/AppData/radarr` (or `/DATA/AppData/...`).
2. **Prowlarr:**
   - Stopped container and copied configuration from `/media/HDD_Data1/appdata/arrstack/prowlarr/config` to SSD AppData.
3. **qBittorrent:**
   - Migrated `/config` to SSD AppData while keeping `/media/HDD_Data1/data/media/downloads` on the HDD.
4. **Jellyfin:**
   - Migrated `/config` (`conf`) to SSD AppData while keeping media streaming mapped to `/media/HDD_Data1/data/media`.
5. **Tailscale:**
   - Migrated state directory to SSD AppData.

---

## 4. Final Container Mount Inspection
After remapping paths via the ZimaOS/CasaOS Web UI, the updated configuration layout was confirmed:

```text
Container: /tailscale
  Host Path: /media/ZimaOS-HD/AppData/tailscale -> Container Path: /var/lib/tailscale

Container: /jellyfin
  Host Path: /media/HDD_Data1/data/media -> Container Path: /Media
  Host Path: /media/ZimaOS-HD/AppData/jellyfin -> Container Path: /config

Container: /qbittorrent
  Host Path: /media/ZimaOS-HD/AppData/qbittorrent -> Container Path: /config
  Host Path: /media/HDD_Data1/data/media/downloads -> Container Path: /DATA

Container: /prowlarr
  Host Path: /media/ZimaOS-HD/AppData/prowlarr -> Container Path: /config

Container: /radarr
  Host Path: /media/ZimaOS-HD/AppData/radarr -> Container Path: /config
  Host Path: /media/HDD_Data1/data/media/movies -> Container Path: /movies

Container: /drive-autosleep
  Host Path: /sys -> Container Path: /sys
  Host Path: /dev -> Container Path: /dev
  Host Path: /DATA/autosleep_both_drives.sh -> Container Path: /autosleep.sh
```

---

## 5. Verifying the Autosleep Script

To confirm that the automated sleep mechanism is fully operational:

1. **Check Script Drive Target:**
   Ensure `/DATA/autosleep_both_drives.sh` lists `/dev/sda` in its active array (`DRIVES=("sda" "sdb" ...)`).
2. **Check Container Logs:**
   ```bash
   sudo docker logs --tail 20 drive-autosleep
   ```
3. **Manual Standby Test:**
   ```bash
   sudo smartctl -s standby,now /dev/sda
   ```
4. **Non-Waking Standby Verification:**
   Query the drive without spinning it up:
   ```bash
   sudo smartctl -n standby /dev/sda
   ```
   *Expected Output:* `Device is in Standby mode`.