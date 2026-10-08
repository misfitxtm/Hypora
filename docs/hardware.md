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
