# Forge — Ubuntu Server Workstation Installer

> **One-liner. Full dev-platform. Air-gap ready.**
>
> Forge bootstraps a complete, enterprise-grade development environment on a
> single physical workstation: a minimal remote-IDE host, a local
> developer VM, and a full DevOps + AI infrastructure VM — all fully
> automated, hermetic, and everything-as-code.

---

## Quick start

One-liner but less secure

```bash
# Download the installer and run
curl -fsSL https://raw.githubusercontent.com/0y0n/forge/main/install.sh | bash

```

To be more secure procedure (**Never pipe scripts directly to bash from the internet.**):

```bash
# 1. Download the installer
curl -fsSL https://raw.githubusercontent.com/0y0n/forge/main/install.sh -o install.sh

# 2. Review the script content
less install.sh

# 3. Make it executable
chmod +x install.sh

# 4. Run as a regular user
./install.sh
```

The script validates the OS, clones this repo, installs Ansible, and runs the playbook.
It uses `sudo` internally for commands that require elevated privileges.

> **Important:** Run as a regular user, not as root. The script will prompt for
> your password when sudo is needed.

> **Prerequisite:** a fresh **Ubuntu Server 25.10 LTS** install on bare metal
> or a VM with at least the specs listed in [Hardware](#hardware).

---

## What Forge provisions

```
remote-workstation          (physical host — this machine)
│
├── NVIDIA host driver
├── gnome minimal desktop + Chrome
├── VS Code + JetBrains Community (IntelliJ / PyCharm / RustRover)
│
└── KVM / QEMU
    ├── dev-workstation     (guest VM)
    │   ├── CUDA Toolkit
    │   ├── Bazel
    │   ├── Java / Python / Rust toolchains + linters / formatters
    │   ├── OpenCode CLI
    │   ├── Sphinx + sphinx-needs / PlantUML / Python4Capella
    │   └── Semgrep / Trivy / Gitleaks
    │
    └── forge-infra         (guest VM)
        ├── Security        Vault
        ├── Network         Traefik · Cilium
        ├── Storage         PostgreSQL · SeaweedFS · DVC
        ├── DevOps          GitLab CE · Artifactory OSS · SonarQube
        ├── AI              Ollama · Qdrant · SearXNG · LiteLLM · Redis
        ├── Observability   Prometheus · Grafana · Loki
        ├── Containers      Podman · podman-compose · Packer · Syft
        └── Orchestration   k3s · Helm · local-path-provisioner
                            └── gitlab-runner
                            └── buildbody-cache   (Bazel remote cache)
                            └── buildbody-executor (Bazel remote exec)
```

---

## Hardware

The reference prototype runs on:

| Component | Spec |
|-----------|------|
| CPU | Intel i7-13700K |
| RAM | 64 GB |
| GPU | NVIDIA RTX 4070 12 GB VRAM |
| Storage | Samsung 990 Pro NVMe |

Default VM allocation leaves ~16 GB and all physical cores available to the
host at idle.  Adjust `vm_dev_workstation` / `vm_forge_infra` in
`inventory/group_vars/remote_workstation.yml`.

---

## Repository layout

```
.
├── install.sh                          # bootstrap (curl | bash entry-point)
├── ansible.cfg                         # paths, callbacks, fact cache
│
├── inventory/
│   ├── hosts.yml                       # 3-host static inventory
│   └── group_vars/
│       ├── all.yml                     # version pins & shared paths
│       ├── remote-workstation.yml      # VM specs, NVIDIA branch
│       ├── dev-workstation.yml         # Bazel remote endpoints
│       └── forge-infra.yml             # service ports, DB list, k3s pods
│
├── playbooks/
│   └── remote_workstation.yml          # single entry-point: 3 plays in sequence
│
└── roles/                              # 18 self-contained roles
    ├── base/                           # OS check · apt update/upgrade · git
    ├── desktop/                        # XFCE4 (minimal) + Chrome
    ├── nvidia_host/                    # NVIDIA driver on physical host
    ├── nvidia_toolkit/                 # CUDA Toolkit inside VMs
    ├── ide/                            # VS Code + JetBrains Community
    ├── kvm/                            # QEMU/KVM + cloud-init VM provisioning
    ├── dev_tools/                      # language toolchains + linters
    ├── bazel/                          # Bazel build system
    ├── opencode/                       # OpenCode CLI
    ├── docs_tools/                     # Sphinx / PlantUML / Capella
    ├── security_scanning/              # Semgrep / Trivy / Gitleaks
    ├── vault/                          # HashiCorp Vault OSS
    ├── network_policy/                 # Traefik reverse-proxy + Cilium CLI
    ├── databases/                      # PostgreSQL · SeaweedFS · DVC
    ├── devops_stack/                   # GitLab · Artifactory · SonarQube
    ├── ai_stack/                       # Ollama · Qdrant · SearXNG · LiteLLM · Redis
    ├── observability/                  # Prometheus · Grafana · Loki
    ├── containers/                     # Podman · Packer · Syft
    └── orchestration/                  # k3s · Helm · workload manifests
```

---

## How it works

### 1. `install.sh` — bootstrap

| Step | Action |
|------|--------|
| 1 | Assert **Ubuntu Server 25.10** — hard fail otherwise |
| 2 | `apt update && apt upgrade` |
| 3 | Install `git` |
| 4 | Clone this repo into `~/forge` (or pull if already present) |
| 5 | Install Ansible via `pipx` (isolated, no PPA noise) |
| 6 | Execute the playbook |

### 2. Playbook — three plays, one file

`playbooks/remote_workstation.yml` contains three plays that run in order:

1. **Play 1 — physical host:** desktop, drivers, IDEs, KVM.  The `kvm` role
   provisions both guest VMs using Ubuntu cloud-init images, waits for SSH,
   then control passes to the next play.
2. **Play 2 — `dev-workstation` guest:** CUDA, Bazel, language toolchains,
   security scanners, doc tooling.
3. **Play 3 — `forge-infra` guest:** the full infrastructure stack —
   Vault, Traefik, Cilium, databases, DevOps apps, AI stack,
   observability, and finally k3s with the three ephemeral workloads.

### 3. Idempotency

Every role is designed to be re-runnable.  Re-running the playbook after a
partial failure or a config change converges without wiping state.

---

## Service ports (forge-infra)

| Service | Port | Protocol | Notes |
|---------|------|----------|-------|
| Traefik (HTTP) | 80 | HTTP | Reverse proxy entry point |
| Traefik (HTTPS) | 443 | HTTPS | Reverse proxy entry point |
| GitLab | 8443 | HTTPS | Web UI |
| Artifactory | 8081 | HTTP | Web UI |
| SonarQube | 9000 | HTTP | Web UI |
| Vault | 8200 | HTTP | API & UI |
| Prometheus | 9090 | HTTP | Metrics & UI |
| Grafana | 3000 | HTTP | Dashboard UI |
| Loki | 3100 | HTTP | Log aggregation API |
| Ollama | 11434 | HTTP | LLM inference API |
| LiteLLM | 4000 | HTTP | LLM proxy API |
| Qdrant | 6333 | HTTP | Vector DB API |
| SearXNG | 8888 | HTTP | Search aggregator UI |
| Redis | 6379 | TCP | Cache & message broker |
| PostgreSQL | 5432 | TCP | Database |
| SeaweedFS master | 9333 | HTTP | Object storage master |
| SeaweedFS volume | 8080 | HTTP | Object storage volume |
| k3s API | 6443 | HTTPS | Kubernetes API server |

---

## VM specs (defaults)

| VM | vCPUs | RAM | Disk | SSH port (host) |
|----|-------|-----|------|-----------------|
| dev-workstation | 8 | 24 GB | 120 GB | 2222 |
| forge-infra | 6 | 24 GB | 200 GB | 2223 |

Tune in `inventory/group_vars/remote_workstation.yml`.

---

## Version pins

All software versions are centralised in `inventory/group_vars/all.yml`.
To upgrade a single tool, change the value there — no role file needs editing.

Key current pins:

| Tool | Variable | Value |
|------|----------|-------|
| Bazel | `bazel_version` | 7.1.1 |
| Traefik | `traefik_version` | v2.11.2 |
| Helm | `helm_version` | v3.14.4 |
| NVIDIA driver branch | `nvidia_driver_branch` | 545 |
| Node | `node_version` | 20 |
| Redis | `redis_version` | 7 |

---

## Offline / air-gap operation

`dev-workstation` is designed to continue working when `forge-infra` is
unreachable.  After an initial fetch/build cycle the local Bazel cache and
source copies are sufficient for day-to-day development.  When infra comes
back online, remote cache (`buildbody-cache`) and remote execution
(`buildbody-executor`) kick in transparently via the Bazel remote
endpoints configured in `inventory/group_vars/dev_workstation.yml`.

---

## Prototype → Enterprise path

Forge is deliberately collapsed onto three machines for fast iteration.
Each layer is designed so that splitting it out later requires only inventory
and variable changes, not role rewrites:

| Prototype | Enterprise target |
|-----------|-------------------|
| Vault file backend | Vault HA (Raft / Consul) |
| SeaweedFS 3 units on one VM | Dedicated SeaweedFS cluster |
| k3s single-node | Managed Kubernetes (EKS / GKE / on-prem) |
| Podman containers | Helm charts in the target k8s |
| local-path PVCs | CSI driver (Ceph / NFS / cloud block) |
| Single Traefik | Ingress controller + cert-manager |
| SQLite / file-based state | Shared NFS or distributed state stores |

---

## Contributing

1. Fork, branch, PR — standard flow.
2. Roles must stay self-contained: `tasks/`, `templates/`, `handlers/`,
   `defaults/` only.  No cross-role hard dependencies except those declared
   in the playbook order.
3. Version pins live in `all.yml`.  Don't hard-code versions inside roles.
4. Keep everything free/open-source.  If a tool has a paid tier, pin to the
   free / community edition explicitly.

---

## License

This project is licensed under the **MIT License** — see [`LICENSE`](LICENSE)
for details.
