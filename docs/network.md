# Network: DNS and MAC addresses

What leaves the machine, and what identifies it on the networks it joins.

[← back to the readme](../readme.md)

## DNS

Plain DNS is the one part of browsing that stays readable to whoever runs the network, long after HTTPS covered everything else: the domain of every site you open, visible to the café router, your ISP and anyone in between, and rewritable by all of them.

Two things fix that, and they pull in opposite directions: encrypting the connection to the resolver, and choosing which resolver you trust. Hypora resolves the tension in favour of **a resolver you control**:

```ini
# /etc/systemd/resolved.conf.d/hypora-dns.conf
FallbackDNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net 2620:fe::fe#dns.quad9.net 2620:fe::9#dns.quad9.net
DNSOverTLS=opportunistic
DNSSEC=allow-downgrade
Cache=yes
```

- **DNS follows the network.** Whatever resolver DHCP hands out is the one used. That's what keeps a Pi-hole, a router or an internal DNS server in charge, with its filtering and its local names intact. `FallbackDNS=` only applies when a network hands out no resolver at all.
- **`DNSOverTLS=opportunistic`** encrypts the connection when the resolver answers on port 853 and uses plain DNS when it doesn't. A Pi-hole on port 53 needs that fallback. The cost is that a network can force plaintext by blocking 853, so this stops someone passively watching, not the network operator itself.
- A second file, `/etc/NetworkManager/conf.d/hypora-dns.conf`, tells NetworkManager to hand its DNS to resolved rather than writing `/etc/resolv.conf` directly — without it, none of the above is consulted.

Check it:

```bash
resolvectl status          # the resolver in use, and DNSOverTLS under Global
resolvectl query github.com
```

### Pinning one resolver

To send every lookup to one resolver regardless of what the network says, set both `DNS=` and `Domains=~.`. The second line is the one that matters: without it resolved keeps using the DHCP servers for most queries and a `DNS=` line does close to nothing.

For a Pi-hole at a static address — worth doing, because it makes routing deterministic instead of depending on what DHCP said:

```ini
DNS=10.0.0.2
Domains=~.
```

For encrypted DNS on untrusted Wi-Fi, strictly, with no plaintext fallback:

```ini
DNS=9.9.9.9#dns.quad9.net 2620:fe::fe#dns.quad9.net
Domains=~.
DNSOverTLS=yes
```

The `#dns.quad9.net` suffix is what makes that encrypted DNS rather than DNS to an encrypted-looking address: it's the name the resolver's certificate has to match. Cloudflare is `1.1.1.1#one.one.one.one`, Mullvad `194.242.2.2#dns.mullvad.net`. Edit the file (or `system/systemd/resolved.conf.d/hypora-dns.conf` and re-run the installer) and `sudo systemctl restart systemd-resolved`.

Note that `DNSOverTLS=yes` breaks captive portals — hotel and airport sign-in pages need DNS to load and block DNS until you've used them. For a one-off, without editing anything:

```bash
sudo resolvectl dnsovertls <interface> opportunistic   # e.g. wlan0; sign in
sudo resolvectl dnsovertls <interface> yes             # then put it back
```

One more knob: `Cache=yes` makes repeat lookups instant, at the cost of hiding them from the resolver, so a Pi-hole's dashboard will undercount. `Cache=no` shows it everything.

## MAC addresses

A network card's permanent MAC address is a unique serial number it broadcasts, unencrypted, at every network it touches. Left alone it's a tracking identifier with no cookie to clear: the same laptop is recognisable across every café, airport and shop it passes, by anyone listening.

`/etc/NetworkManager/conf.d/hypora-mac.conf` randomizes two separate things:

```ini
[device-mac-randomization]
wifi.scan-rand-mac-address=yes

[connection-mac-randomization]
wifi.cloned-mac-address=stable
ethernet.cloned-mac-address=stable
```

**Scanning** is the probe requests a Wi-Fi card broadcasts while looking for networks — constantly, whether or not you ever connect. This is the leak that follows you around a building. NetworkManager already defaults it to on; it's set explicitly so a future change of that default doesn't quietly turn it off.

**Connections** use `stable`, not `random`: one address per connection profile, the same every time you join that network, different for every other network. That defeats cross-network tracking while leaving the things a changing MAC breaks — DHCP reservations, captive portal sessions, router rules keyed to a device — working, because each network still sees one consistent address. `random` is stronger and breaks all of those; `permanent` is the card's real address.

Two consequences worth knowing:

- **The address changes once**, when this first takes effect, so existing DHCP reservations need updating to the new one. To exempt a network instead and keep the real address: `nmcli connection modify "<name>" wifi.cloned-mac-address permanent`.
- **`stable` is derived from the connection profile and `/etc/machine-id`.** Delete and recreate the profile and the address changes again.

Check it:

```bash
nmcli -f GENERAL.HWADDR,GENERAL.PERM-HWADDR device show wlan0
```

When the two differ, it's working. Menu > Security reports the same thing, and flags a card that's on a network using its permanent address.
