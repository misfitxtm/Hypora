# Hardware, drivers and firmware

Finding hardware that did not come up, and fixing what Fedora can fix.

[← back to the readme](../readme.md)

## Hardware, drivers and firmware

A fresh install coming up with no Wi-Fi or Bluetooth is almost never one cause on Fedora, and the three look identical from the desktop:

1. the firmware package isn't installed,
2. the driver never bound to the device, or
3. the radio is switched off in software (rfkill).

`bin/hypora-hardware` tells them apart. The installer runs it, and you can at any time:

```bash
hypora-hardware probe      # what's present, what's wrong (no root)
sudo hypora-hardware fix   # install firmware, load drivers, unblock radios
```

It reads sysfs rather than the kernel log, because `kernel.dmesg_restrict` is 1 on Fedora — firmware errors need root to read, and a probe you have to `sudo` is a probe nobody runs. For each Wi-Fi, Bluetooth, ethernet, GPU and camera device it reports the bound driver, whether Fedora's firmware package for that vendor is installed, and the rfkill state. Where nothing is bound it asks `modprobe -R` what the kernel *would* use, which separates "needs loading" from "no driver exists".

**It will not add a third-party repository.** Fedora splits `linux-firmware` into about two dozen per-vendor packages and that covers most hardware, but not all — Broadcom's `wl` is the usual gap. Those are named and explained, never installed.

**NVIDIA** gets nouveau, the in-tree open driver, together with Fedora's own `nvidia-gpu-firmware` (the GSP firmware modern cards need). That is the open-source driver and it needs no third-party repo. NVIDIA's own driver — including their "open kernel modules" flavour, which is still a proprietary userspace — lives in RPM Fusion, and Hypora doesn't add it for you. If you want it, that's a deliberate step you take.

One cross-check worth knowing: if a camera is present but `uvcvideo` isn't loaded, the probe points at **Menu > Security**, since Hypora's own camera toggle unloads that module.

## Bluetooth connects, then the audio drops

On a desktop with a Wi-Fi and Bluetooth card (Intel AX200 and similar), check that the antenna is screwed onto the card's two small connectors. Cards usually ship with the antenna separate, and Wi-Fi at short range can look fine without it, so nothing seems wrong until you stream Bluetooth audio.

Without the antenna, the radio runs on stray signal from the board. Headphones pair and connect, then go silent or disconnect within a minute of playing. The signs:

- `journalctl -b | grep -i "completion reports"` shows `Missing completion reports for packet ... Bluetooth adapter firmware bug?`
- `bluetoothd` logs `Connection timed out`, `Host is down` or `Connection reset by peer` for the headphones
- `bluetoothctl scan on` shows nearby devices at -90 to -100 dBm; the same devices read -68 to -81 dBm once the antenna was connected

Software changes (codec, power settings, re-pairing, reinstalling BlueZ) do not fix this. Laptops have the antenna built in, so this is a desktop problem.

## Smart cards and YubiKeys

`pcsc-lite`, `pcsc-lite-ccid` (the reader driver) and `opensc` (PIV, CAC and other PKCS#11 tokens, YubiKey PIV included) are core packages, and `pcscd.socket` is enabled. Check with `hypora-smartcard status`. `yubikey-manager` (`ykman`) and `fido2-tools` (`fido2-token`) are core packages, and the optional apps include Yubico Authenticator. FIDO2 keys and passkeys need no setup, because systemd's udev rules already give you access to the key and the browsers can see USB devices. `hypora-smartcard status` lists the YubiKeys and FIDO2 keys it finds.

The Flatpak browsers (Firefox, Chrome, Chromium) cannot see the host's OpenSC, so the installer runs `hypora-smartcard setup`. It copies the OpenSC libraries into each browser's data folder, gives it the `pcsc` socket, and registers the module in its certificate database. Re-run it after installing a browser or upgrading OpenSC. Hypora does not trust any CA for you: a card's issuer (DoD, a company, a university) has to be imported into the browser yourself.
