# Storage: snapshots and swap

btrfs snapshots, and why Hypora would rather you had no swap partition at all.

[← back to the readme](../readme.md)

## Snapshots

Where `/` or `/home` is btrfs, the installer sets up **snapper** with a config for each, plus the timeline and cleanup timers.

**btrfs-assistant** is installed alongside it as a GUI — browse snapshots, create and restore them, edit the configs — because finding *which* snapshot you want is the part that genuinely benefits from a list you can click. On the command line:

```
snapper list                                  # what you have
snapper -c root create -d "before I try this" # one on demand
snapper -c root status 42..43                 # what changed between two
snapper -c root undochange 42..43             # put those files back
```

> **Snapshots are not backups.** They live on the same filesystem they protect, so a failed drive takes every one of them with it. They are excellent against mistakes — a bad update, a deleted file, a config you broke at 1am — and worth exactly nothing against hardware. Hypora does not set up off-disk backup and does not pretend to; if you want that, `borg` or `restic` do versioned backups to another disk properly, and Déjà Dup if you'd rather click.

**Why snapper and not Timeshift.** Timeshift is the better-known tool and the wrong one on Fedora: its BTRFS mode requires the Ubuntu-style subvolume layout, with `/` on a subvolume literally named `@`. Fedora's installer creates `root` and `home`, so Timeshift never offers BTRFS mode at all — it falls back to RSYNC and copies files, which is a backup, not a snapshot. It does this quietly, which is the worst part. snapper does not care what the subvolumes are called.

**Retention is deliberately modest.** snapper's defaults keep ten hourly, ten monthly and ten yearly snapshots per config, which on a laptop retains a lot of extents for very little benefit. Hypora sets 5 hourly, 7 daily, 4 weekly, 2 monthly, 0 yearly, and a 10-snapshot cap. Change them in `/etc/snapper/configs/root`, or turn timeline snapshots off entirely with `TIMELINE_CREATE="no"`.

**Unattended updates are snapshotted; manual ones are not.** This is a real gap and worth understanding rather than discovering. `python3-dnf-plugin-snapper` is a **dnf4** plugin, and Fedora now runs dnf5, which has no snapper plugin at all — so nothing hooks a `dnf` transaction. Installing that plugin would hook nothing and only look like protection.

What Hypora does instead is cover the case that actually needs it: a systemd drop-in on `dnf5-automatic.service` takes a snapshot of `/` before every unattended update, because that is the one you weren't watching.

```
/etc/systemd/system/dnf5-automatic.service.d/10-hypora-snapshot.conf
```

The `ExecStartPre` there is prefixed with `-`, so a failing snapshot can never stop a security update from installing — an update that applied is worth more than a snapshot that didn't.

For a manual upgrade, take one yourself:

```
sudo snapper -c root create -d "before dnf upgrade" && sudo dnf upgrade
```

**What this is not.** These are not bootable rollbacks. Booting *into* a snapshot needs `grub-btrfs`, which Fedora does not package, so snapper here gives you file-level recovery — compare two snapshots, undo a change, or mount one and copy out of it — not a boot menu entry per snapshot.

### Scrub and balance

Nothing on a stock Fedora runs btrfs's own housekeeping, so where there is btrfs Hypora installs `btrfsmaintenance` and schedules two jobs monthly:

- **scrub** reads every block and checks it against its checksum. This is how bit rot gets found, and it matters *more* once you have snapshots: a corrupted extent is shared by every snapshot that references it, so the longer it goes unnoticed the less a snapshot is worth.
- **balance** reclaims chunks that are allocated but mostly empty — the usual cause of a btrfs filesystem reporting "no space left" while `df` says it is half free.

Two of the four periods it offers are deliberately left off:

- **trim** — Fedora already enables `fstrim.timer`, so this would be a second thing doing the same job.
- **defrag** — defragmenting a filesystem with snapshots **unshares** the extents those snapshots have in common, so it can multiply disk usage rather than tidy it. It is the wrong tool once snapshots exist.

Change any of it in `/etc/sysconfig/btrfsmaintenance`, then `sudo systemctl restart btrfsmaintenance-refresh`.

## Swap

Swap holds whatever was in memory, so a plaintext swap partition on an otherwise encrypted machine is a hole straight through the encryption: anything the kernel paged out — keys, messages, documents — sits on the disk in the clear and stays there after the machine is off.

**The recommended answer is to have no swap partition at all.** Fedora's default since F33 is zram: a compressed block device in RAM, sized `min(ram, 8192)`. It is RAM-backed so nothing reaches the disk, it compresses at roughly 3:1, and it is faster than any SSD. On a 16 GB machine that is around 20 GB of compressed pages before a disk would be touched. Hypora treats zram as safe and reports it as such.

You want *some* swap even with RAM to spare: with none at all the kernel cannot evict anonymous pages, so under pressure it has to shred the page cache instead and reaches OOM sooner. zram fills that role without writing anything down.

### If zram is not enough

**Menu > Security** offers **Add swapfile** when `/` is encrypted and there is no swapfile yet. It runs `hypora-security add-swapfile`, which creates a 4 GB swapfile inside the encrypted root, switches it on, and adds one `nofail` line to `/etc/fstab`.

```
hypora-security add-swapfile [size]    # default 4g
hypora-security remove-swapfile
```

A swapfile inside the root volume is **encrypted because of where it lives**. There is no key to manage, nothing in `/etc/crypttab`, no partition table change and no `resume=` to keep in step.

On btrfs it is created in a subvolume of its own with `btrfs filesystem mkswapfile`, which sets NOCOW and disables compression — both of which btrfs requires of a swapfile. The separate subvolume matters for a second reason: **a swapfile caught in a snapshot pins its full size in extents for as long as that snapshot lives.**

It is only offered when `/` is encrypted. A swapfile on a plaintext root is plaintext swap, which is the problem rather than the fix, and the command refuses rather than quietly creating one.

### Why not encrypt a swap partition in place

Hypora used to offer exactly that — a plain dm-crypt layer over the swap partition, keyed from `/dev/urandom` so it was re-keyed every boot. It was removed because **it made a machine unbootable**, and the reason it could is instructive.

Encrypting a swap partition in place means touching three pieces of boot-critical state at once: a `/etc/crypttab` entry, the partition's GPT type (so `systemd-gpt-auto-generator` stops claiming it), and the `resume=` kernel argument, which points at a swap signature that encrypting the device destroys. Each had a defect — a missing `nofail`, a device spelling crypttab need not resolve, and a `resume=` left dangling — and any one of them was enough to stop the boot before the passphrase prompt appeared.

A swapfile has none of that surface. The worst outcome of a failure is a machine that boots without swap.

If you have a plaintext swap partition today, the Security window says so but does not offer to encrypt it. Removing a partition is destructive and belongs in an installer, not behind a button in a settings window — so the advice is to drop it at your next install, let zram do the work, and add a swapfile here if you ever need more.

### Hibernation

Not available, and not because of any of this. Secure Boot puts the kernel in lockdown `integrity` mode, and lockdown blocks hibernation outright — resuming from an unverified memory image would let anyone with disk access substitute a kernel. Check with `cat /sys/power/state`: no `disk` means the kernel will not hibernate whatever swap you have.

Worth knowing that hibernation is the greater hazard anyway. It writes all of RAM to disk, including the LUKS key held in memory while the system runs — so hibernating to plaintext swap writes the keys protecting the disk onto that disk.
