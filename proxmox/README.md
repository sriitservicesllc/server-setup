# Proxmox VE — Template & Service Provisioning Scripts

Bash automation for building reusable **KVM VM** and **LXC container** templates on a
Proxmox VE host, cloning fleets of servers from them, deploying a set of
infrastructure services into dedicated LXC containers, and protecting everything
with scheduled snapshots + offsite backups.

> **Origin:** these scripts and this guide were produced from the design
> conversation at
> <https://gemini.google.com/share/b2acdfc33969>
> ("Proxmox Cloud-Init Template Setup Guide").

---

## ⚠️ Read before running

- **Every script runs on the Proxmox VE host itself, as `root`** (via the node
  shell or SSH). They call `qm`, `pct`, `pveam`, `vzdump` directly.
- **Placeholder credentials are hard-coded** in several scripts
  (`SecurePassword123!`, `ChangeMeImmediately123!`, `ChangeMeInProd123!`,
  `AdminPass123`, `ChangeMeInProdRedisPass123!`). Change them before any real
  use, and prefer SSH keys over passwords.
- Default network assumptions: bridge `vmbr0`, gateway `192.168.1.1`,
  nameserver `1.1.1.1`, static IPs in `192.168.1.0/24`. Edit the config block at
  the top of each script to match your environment.
- Default storage: `local-lvm` for VM/CT root disks, `local` for downloaded
  appliance templates and backups.
- Scripts are idempotent on the "already exists" check — they skip a VM/CT whose
  ID is already present rather than clobbering it.

---

## Prerequisites

```bash
# One-time, on the Proxmox host:

# For the LXC service scripts — make a Debian 12 appliance available.
# (create-lxc-template.sh auto-detects the newest point release; the fixed-name
#  service scripts below expect this specific tarball to be present.)
pveam update
pveam download local debian-12-standard_12.7-1_amd64.tar.zst

# An SSH public key on the host for injection into guests (optional but recommended)
ls ~/.ssh/id_rsa.pub   # or generate: ssh-keygen -t ed25519
```

`create-proxmox-template.sh` additionally installs `libguestfs-tools` on the host
automatically (used to inject the QEMU guest agent into the cloud image).

---

## Script index

| # | Script | Runs on | Purpose | Default ID(s) |
|---|--------|---------|---------|---------------|
| 1 | [`create-proxmox-template.sh`](create-proxmox-template.sh) | Proxmox host | Build the **KVM** golden template from the Ubuntu 24.04 cloud image + Cloud-Init | VM `9000` |
| 2 | [`deploy-proxmox-vms.sh`](deploy-proxmox-vms.sh) | Proxmox host | Batch-clone KVM VMs from template `9000`, resize disk, inject Cloud-Init network/credentials, boot | VM `201`–`203` |
| 3 | [`create-lxc-template.sh`](create-lxc-template.sh) | Proxmox host | Build the **LXC** golden template from the latest Debian 12 appliance + base packages | CT `8000` |
| 4 | [`deploy-lxc-batch.sh`](deploy-lxc-batch.sh) | Proxmox host | Batch-clone LXC containers from template `8000`, resize, set network/SSH/root password, start | CT `301`–`303` |
| 5 | [`lxc-db.sh`](lxc-db.sh) | Proxmox host | Dedicated LXC running **PostgreSQL 16 + Redis** (combined data tier) | CT `401` |
| 6 | [`lxc-network.sh`](lxc-network.sh) | Proxmox host | Dedicated LXC running **Pi-hole** (DNS + ad-blocking), unattended install | CT `402` |
| 7 | [`lxc-monitoring.sh`](lxc-monitoring.sh) | Proxmox host | Dedicated LXC running **Prometheus + Grafana** | CT `403` |
| 8 | [`lxc-gitea.sh`](lxc-gitea.sh) | Proxmox host | Dedicated LXC running **Gitea** (binary + systemd unit, SQLite backend) | CT `404` |
| 9 | [`deploy-redis-lxc.sh`](deploy-redis-lxc.sh) | Proxmox host | **Standalone, memory-tuned Redis** LXC + host-level kernel tuning (overcommit, THP, somaxconn) | CT `406` |
| 10 | [`lxc-backup-and-snapshot.sh`](lxc-backup-and-snapshot.sh) | Proxmox host (cron) | Daily `pct snapshot` with retention pruning + compressed `vzdump` archives | CT `401`–`406` |
| 11 | [`vzdump-rclone-hook.sh`](vzdump-rclone-hook.sh) | Proxmox host (vzdump hook) | On `backup-end`, push each `.tar.zst` to an `rclone` cloud remote; prune remote copies > 30 days | — |

> A Jellyfin media-server LXC (CT `405`, GPU `/dev/dri` passthrough) is described in
> the source conversation but no script file is included here. CT `405` is still
> covered by the backup script's default ID list.

---

## Usage

### Track A — KVM virtual machines (Cloud-Init)

```bash
chmod +x create-proxmox-template.sh deploy-proxmox-vms.sh

# 1. Build the template once (downloads Ubuntu 24.04 cloud image,
#    injects qemu-guest-agent, attaches Cloud-Init drive, `qm template`).
./create-proxmox-template.sh

# 2. Edit the VMS=( ... ) array in deploy-proxmox-vms.sh, then:
#    Format per line: "VM_ID:VM_NAME:IP/CIDR:CORES:MEMORY_MB"  (use "dhcp" for IP)
./deploy-proxmox-vms.sh
```

Because `qemu-guest-agent` is baked into the template, each VM reports its real
IP in the Proxmox summary within ~30–60 s of first boot. Cloud-Init expands the
root partition to fill the resized disk automatically.

### Track B — LXC containers

```bash
chmod +x create-lxc-template.sh deploy-lxc-batch.sh

# 1. Build the LXC template once (auto-detects newest debian-12-standard,
#    boots container, installs curl/wget/sudo/openssh-server/ca-certificates,
#    cleans apt cache, `pct template`).
./create-lxc-template.sh

# 2. Edit the CONTAINERS=( ... ) array in deploy-lxc-batch.sh, then:
#    Format per line: "CT_ID:HOSTNAME:IP/CIDR:CORES:MEMORY_MB:DISK_SIZE"
./deploy-lxc-batch.sh
```

### Track C — Service containers (independent, run any subset)

Each of these creates its **own** container directly from the Debian 12 appliance
(they do **not** depend on the `8000` template). Run only the ones you want:

```bash
chmod +x lxc-db.sh lxc-network.sh lxc-monitoring.sh lxc-gitea.sh deploy-redis-lxc.sh

./lxc-db.sh           # CT 401 — Postgres 5432 + Redis 6379
./lxc-network.sh      # CT 402 — Pi-hole  http://<ip>/admin
./lxc-monitoring.sh   # CT 403 — Grafana :3000 (admin/admin), Prometheus :9090
./lxc-gitea.sh        # CT 404 — Gitea    http://<ip>:3000
./deploy-redis-lxc.sh # CT 406 — standalone tuned Redis :6379
```

`lxc-db.sh` opens PostgreSQL to `0.0.0.0/0` with `md5` auth and binds Redis to
`0.0.0.0` — fine on a trusted VLAN, otherwise tighten `pg_hba.conf` / add a
firewall rule.

`deploy-redis-lxc.sh` also writes host kernel settings to
`/etc/sysctl.d/99-redis.conf` (`vm.overcommit_memory=1`,
`net.core.somaxconn=1024`) and disables Transparent Huge Pages at runtime — these
are host-wide and cannot be set from inside an unprivileged container.

### Track D — Backups

```bash
# Scheduled snapshots + vzdump archives
install -m 0755 lxc-backup-and-snapshot.sh /usr/local/bin/lxc-backup-and-snapshot.sh
crontab -e
# 30 2 * * * /usr/local/bin/lxc-backup-and-snapshot.sh >> /var/log/pve-lxc-backup.log 2>&1

# Offsite sync via rclone (configure a remote first: `rclone config`)
install -m 0755 vzdump-rclone-hook.sh /usr/local/bin/vzdump-rclone-hook.sh
# Global integration — every vzdump job triggers the hook:
echo 'script: /usr/local/bin/vzdump-rclone-hook.sh' >> /etc/vzdump.conf
# ...or per-run:  vzdump 406 --storage local --compress zstd --script /usr/local/bin/vzdump-rclone-hook.sh
```

Retention defaults: 7 rolling `auto_*` snapshots per CT, 3 local `vzdump`
archives per CT, remote copies pruned after 30 days. Edit
`RCLONE_REMOTE` / `REMOTE_BUCKET` / `BANDWIDTH_LIMIT` in the hook script.

---

## Default ID & address map

| Kind | ID | Name | Address | Notes |
|------|----|------|---------|-------|
| VM template | 9000 | `ubuntu-2404-template` | — | Ubuntu 24.04, Cloud-Init |
| VM | 201 | `web-node-01` | 192.168.1.51/24 | 2c / 4096 MB |
| VM | 202 | `db-node-01` | 192.168.1.52/24 | 4c / 8192 MB |
| VM | 203 | `app-node-01` | dhcp | 2c / 2048 MB |
| CT template | 8000 | `debian-base-template` | — | Debian 12, `nesting=1` |
| CT | 301 | `lxc-web-01` | 192.168.1.71/24 | from template 8000 |
| CT | 302 | `lxc-cache-01` | 192.168.1.72/24 | from template 8000 |
| CT | 303 | `lxc-dns-01` | dhcp | from template 8000 |
| CT | 401 | `db-postgres-redis` | 192.168.1.101/24 | Postgres + Redis |
| CT | 402 | `net-dns-pihole` | 192.168.1.102/24 | Pi-hole |
| CT | 403 | `mon-prometheus-grafana` | 192.168.1.103/24 | Prometheus + Grafana |
| CT | 404 | `dev-gitea` | 192.168.1.104/24 | Gitea |
| CT | 405 | `media-jellyfin` | 192.168.1.105/24 | (no script here; in backup list) |
| CT | 406 | `cache-redis-standalone` | 192.168.1.106/24 | tuned standalone Redis |

---

## Troubleshooting

**`400 Parameter verification failed. template: no such template`**
The hard-coded appliance name (`debian-12-standard_12.7-1_amd64.tar.zst`) no
longer matches the current point release in the Proxmox index. Check the exact
name and download it:

```bash
pveam available --section system | grep debian-12
pveam download local debian-12-standard_12.<N>-1_amd64.tar.zst
```

`create-lxc-template.sh` already auto-resolves the newest
`debian-12-standard` via `pveam available … | sort -V | tail -n 1`; the
fixed-name service scripts (`lxc-db.sh` etc.) need the tarball updated by hand or
the same lookup pasted in.

**`unable to create CT … - no such logical volume pve/8G`**
Some `pct` CLI parsers read `--rootfs local-lvm:8G` as a *volume name* instead of
a size. Use a bare number and the explicit `volume=` form:

```bash
DISK_SIZE="8"
pct create ... --rootfs "volume=${STORAGE_POOL}:${DISK_SIZE}" ...
```

**Snapshot rollback / restore**

```bash
pct listsnapshot 401
pct rollback 401 auto_20260902_023000
pct restore 501 /var/lib/vz/dump/vzdump-lxc-401-2026_09_02.tar.zst --storage local-lvm
```

---

## KVM VM vs. LXC — quick reference

| | KVM VM | LXC container |
|--|--------|---------------|
| Kernel | Own isolated kernel | Shares the host kernel |
| Boot time | 20–40 s | 1–2 s |
| Config mechanism | `qemu-guest-agent` + Cloud-Init | host-side `pct set` / `pct exec` |
| OS support | Any (Linux, Windows, BSD) | Linux only |
| Docker inside | Native | needs `nesting=1`, `keyctl=1` |
| Host storage bind-mount | via virtual disk / NFS | direct `mp0` bind-mount, zero overhead |
| Use for | firewalls/routers, k8s nodes, untrusted/multi-tenant, custom kernels | DBs & caches, DNS/proxy/VPN, monitoring, Git tooling, GPU transcoding |
