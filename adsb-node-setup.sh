#!/usr/bin/env bash
# =====================================================================
# adsb-node-setup.sh
# Rebuilds the ADS-B decoder node (Orange Pi Zero / Orange Pi 3) from a
# fresh Armbian Minimal install. See README.md for the full procedure.
#
# What this node does: decodes 1090 MHz with an RTL-SDR (FlightAware
# Pro Stick Plus) using readsb, and publishes a Beast feed on TCP 30005.
# Everything else (map, graphs, FlightAware/PiAware) runs on the
# "adsb-dash" LXC in Proxmox, which pulls from this port.
#
# Usage:  sudo bash adsb-node-setup.sh
# Safe to re-run.
# =====================================================================
set -euo pipefail

### ---------------- Settings (edit if needed) ----------------
NODE_HOSTNAME="adsb-node"
TIMEZONE="America/Detroit"
GAIN=""          # blank = installer default. Or a number, e.g. "43.9"
### -----------------------------------------------------------

[[ $EUID -eq 0 ]] || { echo "Run with sudo:  sudo bash $0"; exit 1; }
log() { echo -e "\n==> $*"; }

log "Updating system packages"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade
DEBIAN_FRONTEND=noninteractive apt-get -y install \
  curl wget ca-certificates netcat-openbsd unattended-upgrades

log "Setting hostname ($NODE_HOSTNAME) and timezone ($TIMEZONE)"
hostnamectl set-hostname "$NODE_HOSTNAME"
grep -q "$NODE_HOSTNAME" /etc/hosts || echo "127.0.1.1 $NODE_HOSTNAME" >> /etc/hosts
timedatectl set-timezone "$TIMEZONE"

log "Enabling automatic security updates"
dpkg-reconfigure -f noninteractive unattended-upgrades

log "Keeping logs in RAM to reduce SD card writes"
if [[ -f /etc/default/armbian-ramlog ]]; then
  sed -i 's/^ENABLED=.*/ENABLED=true/' /etc/default/armbian-ramlog
  echo "armbian-ramlog enabled (takes effect after reboot)"
else
  echo "Not Armbian (no armbian-ramlog). Consider installing log2ram manually."
fi

log "Stopping the kernel's TV-tuner driver from grabbing the SDR"
cat > /etc/modprobe.d/blacklist-rtl-dvb.conf <<'EOF'
blacklist dvb_usb_rtl28xxu
blacklist rtl2832
blacklist rtl2830
EOF
modprobe -r dvb_usb_rtl28xxu 2>/dev/null || true

log "Installing readsb (ADS-B decoder) via wiedehopf's install script"
bash -c "$(wget -qO - https://github.com/wiedehopf/adsb-scripts/raw/master/readsb-install.sh)"

if [[ -n "$GAIN" ]]; then
  log "Setting gain to $GAIN"
  readsb-gain "$GAIN" || echo "WARNING: could not set gain; see README troubleshooting."
fi

systemctl enable readsb
systemctl restart readsb
sleep 5

log "Checking the Beast feed on port 30005"
if ss -tln | grep -q ':30005 '; then
  echo "OK: readsb is publishing on port 30005."
else
  echo "WARNING: nothing listening on 30005. Check: sudo systemctl status readsb"
fi

echo
echo "This node's IP address(es):"
hostname -I
echo
echo "Next: make sure the router reserves 192.168.2.99 for this device"
echo "(or update ULTRAFEEDER_CONFIG on the LXC). Then reboot:  sudo reboot"
