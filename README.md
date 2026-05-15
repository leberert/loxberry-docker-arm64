# loxberry-docker-arm64

LoxBerry running in Docker on ARM64 (Raspberry Pi 3 / 4 / 5 / Zero 2).

The official [LoxBerry installer](https://github.com/mschlenstedt/Loxberry_Installer) only runs on DietPi. This project fakes the DietPi environment inside a Debian 12 (Bookworm) container so the **upstream installer runs unmodified** and produces a working LoxBerry — natively on ARM64.

> ⚠️ **Unofficial.** Not supported by the LoxBerry project. Some plugins that touch hardware (GPIO, 1-Wire) or expect a real init system may not work. Use a native DietPi install if you need full plugin support.

---

## Quick start

```bash
git clone https://github.com/YOUR_USER/loxberry-docker-arm64.git
cd loxberry-docker-arm64
docker compose up -d --build
```

First build takes 20–40 min on a Pi 4. Subsequent builds are cached.

Open: <http://raspi> (or your Pi's IP)

Default credentials:

| User       | Password    |
|------------|-------------|
| `loxberry` | `loxberry`  |
| `root`     | `loxberry`  |

Change both immediately after first login.

---

## Requirements

- Raspberry Pi 3 / 4 / 5 / Zero 2 (or any ARM64 host)
- 64-bit OS (Raspberry Pi OS arm64, Ubuntu arm64, Debian arm64)
- Docker 20.10+ and Docker Compose v2
- ~3 GB free disk, 1 GB+ RAM available to the container

Install Docker if missing:
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# log out / back in
```

---

## Manual run (without compose)

```bash
docker build -t loxberry-arm64 .
docker run -d \
  --name loxberry \
  --hostname loxberry \
  --privileged \
  --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -v loxberry_data:/opt/loxberry \
  -p 80:80 -p 443:443 -p 8022:22 \
  --restart unless-stopped \
  loxberry-arm64
```

---

## Common commands

```bash
docker compose logs -f          # live logs
docker compose restart          # restart
docker compose down             # stop & remove container (data persists in volume)
docker exec -it loxberry bash   # shell inside
```

---

## Files

| File                 | Purpose                                            |
|----------------------|----------------------------------------------------|
| `Dockerfile`         | Debian 12 base + systemd + runs `install.sh`       |
| `install.sh`         | Fakes DietPi, then runs the upstream LB installer  |
| `docker-compose.yml` | Easy deployment with persistent volume             |

---

## Known limitations

- `reboot` / `shutdown` from the LoxBerry UI won't do anything — use `docker restart loxberry`.
- Network config inside LoxBerry has no effect — set hostname/IP via Docker flags.
- Hardware plugins (GPIO, 1-Wire-NG, Bluetooth) **will not work**.
- Updates done through the LoxBerry UI may or may not survive — rebuild the image to upgrade cleanly.

---

## Credits

- [mschlenstedt/Loxberry](https://github.com/mschlenstedt/Loxberry) — the actual LoxBerry project
- [mschlenstedt/Loxberry_Installer](https://github.com/mschlenstedt/Loxberry_Installer) — the installer this wraps
- Inspired by `markuslaube/Loxberry_DockerBuild` and `michaelmiklis/docker-rpi-loxberry`

## License

Apache 2.0 — same as upstream LoxBerry. This project only adds wrapper scripts.
