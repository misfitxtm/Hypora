# Power and battery

Measuring what a laptop draws, and spending less of it.

[← back to the readme](../readme.md)

## Battery

Linux's reputation for poor battery life is mostly about defaults rather than capability. Two of them matter on a Hyprland desktop, and `bin/hypora-power` covers both.

```
hypora-power status      # what it is drawing right now, in watts
sudo hypora-power apply  # apply the settings for the current AC state
sudo hypora-power install  # apply them, and follow the charger from now on
sudo hypora-power remove
```

`install.sh` runs `install` automatically **on laptops only**, and `hypora-power install` refuses on anything else even if run by hand.

The installer decides laptop-or-desktop **once, at the start**, and every laptop-specific step reads that one answer — so they cannot disagree with each other. It prints which it chose and why. `IS_LAPTOP=yes` or `IS_LAPTOP=no` overrides it, for firmware that reports nonsense.

The test is the SMBIOS chassis type, not "does this machine have a battery" — those are different questions. A desktop with a UPS reports `type=Battery`, and so does a paired wireless mouse. The chassis never lies about what the machine is. Where DMI says nothing useful, which is mostly virtual machines, it falls back to looking for a battery whose `scope` is not `Device`, so a peripheral still doesn't count.

That test lives in one place — `hypora-power is-laptop`, which the installer calls rather than reimplementing, because two copies of a distinction that subtle would eventually disagree.

**Nothing switches the power profile.** GNOME flips power-profiles-daemon to power-saver when the charger comes out — but it does that *in the shell*, so a session without GNOME Shell gets no switching at all and sits in `balanced` on battery indefinitely. A udev rule on the mains supply fixes that, calling `hypora-power auto` directly: the work is a handful of sysfs writes and takes milliseconds, where asking systemd to start a unit from a udev rule is the sort of thing that deadlocks at boot.

**The settings follow the profile, not the charger.** The Control Center's **Saver / Balanced / Performance** buttons already set the profile over D-Bus, which needs no privileges. Rather than give those buttons a privileged action — and a password prompt on every press — the system side watches for the profile changing and follows it: `tuned` rewrites `/etc/tuned/active_profile` whenever the profile changes, so a systemd **path unit** on that file is enough. No daemon, no polkit rule, and nothing in the window had to change.

That means one path serves both triggers. The charger coming out sets the profile; pressing a button sets the profile; either way the extra settings follow. Profile names are normalised across both vocabularies, since `tuned` says `powersave` and `throughput-performance` where power-profiles-daemon says `power-saver` and `performance`, and an unrecognised name falls back to balanced rather than guessing.

On a system with power-profiles-daemon but no `tuned`, there is no file to watch: the charger still switches things, but the buttons will only change the profile and not the extra settings. The installer says so rather than leaving you to notice.

**tuned leaves four knobs alone.** Its `powersave` profile covers the CPU governor, energy performance preference, audio codec timeout, SATA link power management and panel power savings — but its `[net]` and `[disk]` sections are empty and it never writes PCIe ASPM, USB autosuspend or PCI runtime power management. On a ThinkPad those are worth more than everything else here put together; a stock Fedora install typically has twenty-plus PCI devices sitting at `power/control=on`.

So Hypora switches the profile and sets only what tuned does not, rather than duplicating a tool that is already doing the job.

Two deliberate restraints:

- **Input devices are never autosuspended.** Any USB device presenting a HID interface is skipped. Autosuspending a mouse or keyboard is the classic way to make a laptop feel broken — the first movement after an idle moment is swallowed while the device wakes — and the saving from a HID device is negligible.
- **PCIe ASPM is set, not forced.** It is frequently read-only, because the firmware never handed ASPM to the kernel. `hypora-power` reports that rather than passing `pcie_aspm=force`, which is a known way to produce instability that is very hard to trace back.

Everything is measured, not assumed. `status` reads `power_now` from the battery — or `current_now` × `voltage_now` on batteries that do not publish power directly — and turns it into watts and an estimated runtime, so you can see what a change actually bought:

```
Power source     battery
Drawing          10.44 W
Battery          72%   about 3h 55m left at this rate
```

For reference, a ThinkPad T480s idling at 10 W has roughly twice the headroom it should; a tuned one sits nearer 5 W, which on the same battery is the difference between about four hours and about eight.

Screen brightness remains the single largest draw on any laptop, and nothing here changes it — that one is yours.
