<img src="icons/icon-256.png" width="128" height="128" alt="teslausb-lite">

# teslausb-lite

A small take on [teslausb](https://github.com/marcone/teslausb): a Raspberry Pi acts as the car's
USB drives and uploads Sentry and dashcam clips with rclone once the car is home.

Not part of the teslausb project, and not affiliated with or endorsed by Tesla, Inc.

## Differences from teslausb

- Clips are read from one snapshot taken when the car reaches the home network. A clip you delete
  in the car before that is never uploaded. teslausb snapshots the drive about once an hour while
  driving and archives everything any of those snapshots held.
- Only SavedClips and SentryClips are uploaded, TeslaTrackMode optionally. RecentClips are not.
- rclone is the only archive backend (OneDrive, Google Drive, SMB, SFTP and so on).
- The light show, wrap, license plate, lock chime, boombox and music drives are filled from a
  cloud folder instead of a web page.
- No web server, Samba, access point or prebuilt image, and Pushover is the only notification
  service. One script, one service and one config file.
- Runs on stock Raspberry Pi OS Lite (trixie) without repartitioning the card. The snapshot is a
  device-mapper snapshot of the cam image.

## Requirements

- A Raspberry Pi with USB device mode: Zero 2 W, 4 or 5.
- Raspberry Pi OS Lite (64-bit), Debian 13 trixie.
- A card that holds the drives plus about 10 GB.
- An rclone remote.

## Install

```bash
git clone https://github.com/mews-se/teslausb-lite.git
cd teslausb-lite
sudo ./install.sh
```

`sudo ./install.sh --ble` also builds tesla-control, see [Keeping the car awake](#keeping-the-car-awake).

Then:

1. Edit `/etc/teslausb-lite.conf`. At least `ARCHIVE_REMOTE`, `HOME_SSID` and the drive sizes.
2. Put an rclone config in `/root/.config/rclone/rclone.conf`, either with `sudo rclone config`
   (for OneDrive it asks you to run `rclone authorize "onedrive"` on a computer with a browser) or
   by copying an existing one. On a teslausb Pi it is `/mutable/configs/rclone/rclone.conf`.
3. Reboot.

The archive layout is the same as teslausb's (`SavedClips/<event>/`, `SentryClips/<event>/`), so
pointing `ARCHIVE_REMOTE` at the folder teslausb used continues that archive.

## Drives

| Drive     | Holds                                            | Size setting     |
|-----------|--------------------------------------------------|------------------|
| CAM       | `TeslaCam`, `TeslaTrackMode`                     | `CAM_SIZE`       |
| LIGHTSHOW | `LightShow/`, `Wraps/`, `LicensePlate/`, `LockChime.wav` | `LIGHTSHOW_SIZE` |
| BOOMBOX   | `Boombox/`                                       | `BOOMBOX_SIZE`   |
| MUSIC     | `Music/`                                         | `MUSIC_SIZE`     |

A size of 0 leaves the drive out. The car will not play a light show from a drive with a
`TeslaCam` folder, and Tesla asks for the boombox sounds to be alone on their drive, hence the
separate drives. `LockChime.wav` goes in the root of the drive named in `LOCKCHIME_DRIVE`.

All drives are exFAT image files in `/var/lib/teslausb-lite`. To change a size, stop the service,
delete the image and start it again; the content of that drive is lost.

New images plus 8 GB for the snapshot have to fit in the free space; otherwise the service stops
before connecting anything and `teslausb-lite status` says why. The defaults need a 128 GB card.
On a 32 GB card something like `CAM_SIZE=16G`, `LIGHTSHOW_SIZE=256M`, `BOOMBOX_SIZE=0` and
`MIN_FREE=4G` works. Keep `MIN_FREE` below `CAM_SIZE`, or every boot deletes all uploaded clips
from the car.

## Content for the extra drives

Point `CONTENT_REMOTE` at a folder laid out like this:

```
LightShow/xmas.fseq
LightShow/xmas.wav
Wraps/stripes.png
LicensePlate/plate.png
Boombox/horn.wav
Music/...
LockChime.wav
```

The folder is mirrored: delete a file there and it goes from the car too. When something has
changed and the car is home and not recording, the drives disconnect for a few seconds while the
images are updated. That happens at the next look, every `RESCAN_INTERVAL` seconds, or right away
with `sudo teslausb-lite rescan`.

## Archiving

1. At boot every image is checked with fsck. On the cam drive the oldest uploaded events are
   deleted while less than `MIN_FREE` is free; nothing that has not been uploaded is touched. Then
   the drives are connected.
2. When the Pi is on `HOME_SSID` and the remote answers, it waits `ARRIVAL_DELAY` seconds.
3. It takes a snapshot, checks it and mounts it read-only. Every event that has not been uploaded
   with the same file count and size goes up, first into `.partial/` and then moved into place, so
   the archive only holds complete events. An event that grew after its upload gets the new files.
4. While home it looks again every `RESCAN_INTERVAL` seconds if the car has written anything.

State lives in `/var/lib/teslausb-lite`: the images, `uploaded` (what is in the archive) and `log`.

## Notifications

With `PUSHOVER_USER_KEY` and `PUSHOVER_APP_KEY` set, the Pi sends a Pushover message when it
reaches the home network (with the wifi name), when an upload starts (events, files and size), when
it is done (and how long it took) and when an extra drive gets new content. teslausb's config uses
the same two names. When an upload fails, the retries stay quiet until they succeed or the car comes
home again. When the archive remote has not answered for five minutes after the Pi got home, you get
one message saying so; an expired OneDrive token or a missing rclone config would otherwise go
unnoticed. The Pi boots every time the car wakes up, so parked at home the arrival message comes
more than once a day.

## Keeping the car awake

Since 2024.32 the car cuts USB power soon after you leave it, often before a few gigabytes are
uploaded. With `KEEP_AWAKE=yes` the Pi talks to the car over Bluetooth with Tesla's
[tesla-control](https://github.com/teslamotors/vehicle-command): it switches Keep Accessory Power
on when it gets home and off again when everything is uploaded, or after `KEEP_AWAKE_MAX` seconds.
`KEEP_AWAKE_COMMAND=sentry-mode` uses Sentry Mode instead, and switches Sentry off afterwards.

```bash
sudo ./install.sh --ble
sudo teslausb-lite ble-keygen
# set TESLA_VIN in /etc/teslausb-lite.conf, then sit in the car with the key card
sudo teslausb-lite ble-pair
sudo teslausb-lite ble-test
```

The key stays on the Pi in the car, so pair it with the narrowest role that works. `ble-pair` asks
for `charging_manager`; if `ble-test` is refused, remove the key in the car and pair again with
`sudo teslausb-lite ble-pair driver`. A driver key unlocks and drives the car, so if the Pi goes
missing, remove its key under Controls > Locks.

## Commands

```bash
sudo teslausb-lite status
sudo teslausb-lite rescan
journalctl -u teslausb-lite
```

`rescan` makes the Pi look for new clips and new content right away instead of at the next
`RESCAN_INTERVAL`. The car has to be home; otherwise the request waits for the next arrival.

## Updating

```bash
cd teslausb-lite
git pull --ff-only
sudo ./install.sh
sudo systemctl restart teslausb-lite
```

`install.sh` can be run again at any time. It leaves `/etc/teslausb-lite.conf` alone and also updates
rclone, which comes from rclone.org rather than from apt. The drives disconnect for a moment at the
restart, so do it while the car is parked.

Raspberry Pi OS Lite does not update itself. `sudo apt install unattended-upgrades` with its stock
settings gives you Debian's security and point release updates, but not the kernel and firmware from
the Raspberry Pi archive. That is a sensible split for a Pi that loses power whenever the car goes to
sleep: an interrupted kernel upgrade can leave a card that does not boot, while an interrupted
ordinary package is put right with `sudo dpkg --configure -a`. Leave automatic reboots off; the Pi is
power cycled every time the car wakes up, so a new kernel is picked up on the next drive. Upgrade the
kernel and firmware yourself with `sudo apt full-upgrade` now and then.

## Tried in a car so far

On a Pi 4 the car records to the CAM drive, saves clips there and plays `LockChime.wav` from the
LIGHTSHOW drive. Parked at home, the Pi joined the home wifi and uploaded the saved clip that was
still in the car. The rest of the cycle (pruning, keep-awake logic) has been run in a Debian 13 VM
with `dummy_hcd` playing the car. Still to be seen in a real car: whether Keep Accessory Power keeps
the USB ports powered once the car sleeps, wraps and plates next to a light show, and which key role
the car accepts.

## Credits

The approach comes from teslausb (MIT) by cimryan and marcone; no code was taken from it.
tesla-control is part of teslamotors/vehicle-command (Apache-2.0).
