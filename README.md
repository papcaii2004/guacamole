# Guacamole + Fedora xRDP Setup

One-command Apache Guacamole deployment with Docker Compose, designed to RDP into a Fedora server running MATE desktop.

## Architecture

```
Laptop (Browser)
  |
  v
VPS (Guacamole on Docker, port 3389)
  |  Tailscale / VPN
  v
Fedora Server (xRDP + MATE + virt-manager)
```

## Part 1: Guacamole on VPS

### Prerequisites

- Docker + Docker Compose installed on VPS
- Domain (optional): e.g. `guac.duyhn.id.vn` pointed to VPS IP

### Setup

```bash
git clone https://github.com/papcaii2004/guacamole.git
cd guacamole
chmod +x start.sh
./start.sh
```

`start.sh` will:
1. Auto-generate a random Postgres password in `.env`
2. Run an init container to generate DB schema (official method)
3. Start all services: `postgres`, `guacd`, `guacamole`

Access: `http://<VPS-IP>:3389/`
Default login: `guacadmin` / `guacadmin` (change immediately)

### Services

| Service | Role |
|---|---|
| `init-guac-db` | Generates DB schema SQL then exits |
| `postgres` | Stores users and connection config |
| `guacd` | Protocol proxy (handles RDP/VNC/SSH) |
| `guacamole` | Web UI (Tomcat, exposed on port 3389) |

### Notes

- Uses `latest` image tag (no hardcoded version)
- DB auto-initializes via named volume (`dbinit`) mounted into postgres `docker-entrypoint-initdb.d`
- `WEBAPP_CONTEXT=ROOT` so Guacamole serves at `/` instead of `/guacamole/`
- Init container runs as `user: root` to avoid permission denied on volume write

---

## Part 2: Fedora Server (xRDP + MATE)

Tested on Fedora 43 (kernel 6.19.10), xrdp 0.10.5, xorgxrdp 0.10.5, Xorg 21.1.21.

### Install MATE Desktop

Fedora 43 does not have an XFCE group. MATE is the best choice for xrdp (lightweight, stable, excellent xrdp compatibility).

```bash
sudo dnf install -y mate-session-manager mate-panel mate-terminal \
  mate-settings-daemon mate-control-center mate-power-manager \
  caja marco mate-notification-daemon mate-polkit network-manager-applet
```

### Install xRDP + xorgxrdp

```bash
sudo dnf install -y xrdp xorgxrdp
```

### Configure xRDP

#### 1. Uncomment `code=20` in xrdp.ini (CRITICAL)

Without this, xrdp does not recognize the Xorg session type and falls back to VNC.

```bash
sudo sed -i 's/^#code=20/code=20/' /etc/xrdp/xrdp.ini
```

Verify the `[Xorg]` section looks like:

```ini
[Xorg]
name=Xorg
lib=libxup.so
username=ask
password=ask
port=-1
code=20
```

#### 2. Add `ip=127.0.0.1` to `[Xorg]` section

Without this, you get "error - no ip set" message box.

```bash
sudo sed -i '/^\[Xorg\]/,/^port=/{s/^port=-1/ip=127.0.0.1\nport=-1/}' /etc/xrdp/xrdp.ini
```

#### 3. Create Xwrapper config

Allows non-root Xorg startup (required on Fedora):

```bash
echo -e "allowed_users=anybody\nneeds_root_rights=auto" | sudo tee /etc/X11/Xwrapper.config
```

#### 4. Configure user session to use MATE

```bash
cat > ~/.xsession << 'EOF'
export XDG_SESSION_TYPE=x11
exec dbus-run-session mate-session
EOF
chmod +x ~/.xsession
```

#### 5. Enable and start xRDP

```bash
sudo systemctl enable --now xrdp xrdp-sesman
```

#### 6. Open firewall

```bash
sudo firewall-cmd --add-port=3389/tcp --permanent
sudo firewall-cmd --reload
```

### Create RDP Connection in Guacamole

In Guacamole web UI: Settings > Connections > New Connection

| Parameter | Value |
|---|---|
| Protocol | RDP |
| Hostname | Fedora server IP (e.g. Tailscale IP) |
| Port | 3389 |
| Username | your fedora user |
| Password | your password |
| Ignore server certificate | true |
| Security mode | NLA or Any |
| Color depth | 16-bit (reduces lag) |
| Disable wallpaper | true |
| Disable theming | true |
| Disable font smoothing | true |
| Disable full window drag | true |
| Disable menu animations | true |
| Disable desktop composition | true |

---

## Troubleshooting

### "Error connecting to user session" / "no ip set"

- Ensure `ip=127.0.0.1` and `code=20` are set in `[Xorg]` section of `/etc/xrdp/xrdp.ini`

### "lib_data_in: bad size" / "Xorg server closed connection"

- Kill stale sessions: `sudo pkill -u <user> Xorg && sudo rm -rf /tmp/.xrdp /tmp/.X11-unix/X1*`
- Restart: `sudo systemctl restart xrdp xrdp-sesman`
- Check ABI compatibility: `rpm -q xrdp xorgxrdp xorg-x11-server-Xorg`
- If versions mismatch, downgrade: `sudo dnf downgrade -y xrdp xorgxrdp`

### "Certificate validation failed" (from guacd)

- Set "Ignore server certificate" to `true` in Guacamole connection settings

### "could not acquire name on session bus"

- Fix `.xsession` to use `dbus-run-session`:
  ```
  exec dbus-run-session mate-session
  ```

### RDP lag

- Reduce color depth to 16-bit
- Disable all visual effects (wallpaper, theming, font smoothing, etc.)
- Check latency between VPS and Fedora: `ping <fedora-ip>` (should be < 50ms)

### Stale sessions prevent new connections

```bash
sudo pkill -u <user> Xorg
sudo pkill -u <user> Xvnc
sudo rm -rf /tmp/.xrdp /tmp/.X11-unix/X1*
sudo systemctl restart xrdp xrdp-sesman
```

### SELinux blocking xrdp (test)

```bash
sudo setenforce 0   # temporary, for testing only
```

If this fixes the issue, create a proper policy:

```bash
sudo ausearch -c 'xrdp' --raw | audit2allow -M my-xrdp
sudo semodule -i my-xrdp.pp
sudo setenforce 1
```
