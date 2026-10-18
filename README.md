# ADS-B Receiver Node — Rebuild Guide

Written for future me, assuming I remember nothing.

## What this is

A small Orange Pi with a USB SDR dongle and an antenna on the house. It
listens to aircraft transponders (1090 MHz ADS-B) and streams the decoded
data over the network. It does **nothing else**. The map, graphs, and
FlightAware feeding all happen on a Proxmox container.

```
 Antenna ─► Pro Stick Plus (USB SDR) ─► Orange Pi "adsb-node"
                                         readsb decoder
                                         publishes Beast feed, TCP 30005
                                               │  (Wi-Fi or Ethernet)
                                               ▼
                        Proxmox LXC "adsb-dash" (Ubuntu 24.04, Docker)
                          ultrafeeder container ─► tar1090 map  :8080
                                                 ─► graphs     :8080/graphs1090
                          PiAware (built from source) ─► FlightAware + MLAT
```

Because the Pi only streams data and keeps logs in RAM, it barely writes
to its SD card. If it dies, nothing of value is lost. Rebuild it and the
LXC picks the feed back up automatically.

## Where things live

| Thing | Location |
|---|---|
| Decoder node IP | **192.168.2.99** (DHCP reservation on the router) |
| Decoder software | `readsb`, service `readsb`, config `/etc/default/readsb` |
| Dashboard container | Proxmox LXC, hostname `adsb-dash` |
| Dashboard config | `~/adsb-dash/docker-compose.yml` on the LXC |
| Link between them | `ULTRAFEEDER_CONFIG=adsb,192.168.2.99,30005,beast_in` in that compose file |
| FlightAware feeder | PiAware on the LXC, reads `127.0.0.1:30005` from ultrafeeder |
| Rebuild script | `adsb-node-setup.sh` (next to this README) |

## Rebuild procedure (about 30 minutes)

### 1. Flash the OS
1. Download **Armbian Minimal / CLI** (Debian, no desktop) for the board
   from armbian.com. Search the site for the exact model (e.g. "Orange Pi Zero").
2. Write it to a microSD card with balenaEtcher or Raspberry Pi Imager.
   Use a name-brand card (Samsung, SanDisk, PNY). Avoid no-name eBay cards.

### 2. First boot (headless)
1. Plug the Pi into **Ethernet** and power it on. It gets an address by DHCP.
2. Find its IP in the router's DHCP list (or `nmap -sn 192.168.2.0/24`).
3. `ssh root@<ip>`. Default password is `1234`. It will make you set a new
   root password, create a normal user, and pick a timezone/locale.

### 3. Network
- **Ethernet** is the most reliable option. The original Orange Pi Zero's
  built-in Wi-Fi is notoriously poor.
- **For Wi-Fi:** run `sudo armbian-config`, open the Network section, and
  join the network. Test it with Ethernet unplugged: `ping -c 100 1.1.1.1`.
  If it drops packets, use a cheap USB Wi-Fi adapter instead.

### 4. Run the setup script
Copy the script over and run it:
```
scp adsb-node-setup.sh <user>@<ip>:~
ssh <user>@<ip>
sudo bash adsb-node-setup.sh
```
It updates the OS, sets the hostname, keeps logs in RAM, installs readsb,
and checks that port 30005 is live.

### 5. Fix the IP address
In the router, give this device's MAC address a **DHCP reservation for
192.168.2.99**. That's what the dashboard expects. Find the MAC with
`ip link`.
If that address can't be used, change the IP in `ULTRAFEEDER_CONFIG` in
`~/adsb-dash/docker-compose.yml` on the LXC, then run
`sudo docker compose up -d` in that folder.

### 6. Reboot and verify
```
sudo reboot
```
Then check:
- **On the Pi:** `sudo systemctl status readsb` shows active (running).
- **From any computer:** `nc 192.168.2.99 30005 | head -c 200 | xxd` shows
  binary data. Lots of `1a 33` / `1a 32` means aircraft messages.
- **Map:** open `http://<adsb-dash-ip>:8080`. Planes should appear within a minute.
- **FlightAware:** your stats page shows the feeder online.

## Optional: back up the finished card
Once it's working, image the card from another Linux machine:
```
sudo dd if=/dev/sdX of=adsb-node.img bs=4M status=progress
```
(Check the device name with `lsblk` first.) Next time, just flash the
image and skip steps 3–6.

## Orange Pi 3 only: move to eMMC
The Orange Pi 3 has onboard eMMC. After step 4, run `sudo armbian-install`
and choose "Boot from eMMC – system on eMMC". Power off, remove the SD
card, and power on.

## Troubleshooting

| Symptom | Fix |
|---|---|
| No planes, readsb running | Is the dongle seen? `lsusb` should list a Realtek RTL2838 device. Try another USB port. |
| `usb_claim_interface error` | The TV driver grabbed the dongle. Reboot (the script blacklists it). |
| Weak reception / few planes | Gain. Try `sudo readsb-gain 43.9`, then lower values. The Pro Stick Plus has a built-in amp, so it often wants less gain than a plain dongle. |
| Map empty, Pi is fine | Check the LXC is running (Proxmox: Start at boot = Yes) and that the Pi's IP matches `ULTRAFEEDER_CONFIG`. |
| FlightAware offline | Problem is on the LXC, not the Pi. `sudo systemctl status piaware` there. PiAware was built from source with `piaware_builder` and doesn't auto-update; rebuild it every few months. |
| readsb install script fails | The script lives at github.com/wiedehopf/adsb-scripts. Check there for current instructions. |

## Hardware notes
- SDR: FlightAware Pro Stick Plus (built-in LNA and 1090 MHz filter).
  Any RTL-SDR works for testing. An RTL-SDR Blog **V4** needs RTL-SDR Blog's
  newer driver.
- Antenna height matters more than anything else. Higher and outdoors
  gives the biggest range gains.
- Power: use a decent 5V supply. Brownouts corrupt SD cards more than wear does.
