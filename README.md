# OrbStack-ELK — Isolated Malware Analysis Lab

A self-contained dynamic-analysis environment for detonating malware inside an
isolated Linux sandbox while capturing its behaviour with the Elastic Stack
(Elasticsearch + Kibana + Fleet, **no Logstash**), Falco, Zeek and an INetSim
fake-internet sinkhole.

## Architecture

```
                    macOS host (OrbStack: shared Docker engine)
 ┌───────────────────────── elk-net (bridge) ─────────────────────────┐
 │  elasticsearch:9200   kibana:5601   fleet-server:8220               │
 │        ▲                                   ▲                        │
 │        │ data (auth)                       │ enroll                 │
 │        └───────────────  elastic-agent (Fleet-managed) ────────────┘
 │                          privileged, pid:host, /hostfs:ro
 │                          reads: falco / zeek / inetsim log volumes
 └────────────────────────────────────────────────────────────────────
                    ▲ falco-logs   ▲ zeek-logs   ▲ inetsim-logs (volumes)
 ┌──────────────── malware-net (internal: no route off-host) ─────────┐
 │  malware-sandbox (victim, DNS→10.66.6.10)   sinkhole 10.66.6.10     │
 │  falco (pid:host, none-net)   zeek (shares sandbox netns)          │
 └────────────────────────────────────────────────────────────────────
```

- **elk-net** — management plane. Only the collector agent sits here; the sample never does.
- **malware-net** — `internal: true`, so the sandbox has **no route off the host**. All its
  DNS resolves to the INetSim sinkhole, which serves fake HTTP/S, FTP, SMTP, DNS, etc.

## Data coverage

| Pillar | Source (verified working) | Elasticsearch data stream |
|---|---|---|
| Syscalls | Falco (modern eBPF) | `logs-falco-*` |
| Process behaviour | Falco (`execve`/`clone`/memfd), System integration | `logs-falco-*`, `metrics-system.process-*` |
| Network activity | Zeek JSON (conn/dns/http/ssl/files) + INetSim request logs | `logs-zeek-*`, `logs-inetsim-*` |
| Config changes ("registry" on Linux) | File Integrity Monitoring (`/etc`, cron, ssh, bins) + Falco | `logs-fim.event-*`, `logs-falco-*` |
| File activity | FIM + Falco file syscalls | `logs-fim.event-*`, `logs-falco-*` |
| Memory artifacts | `scripts/memory-capture.sh` (maps/regions/libs/fds + optional core), Osquery | `malware-memory-artifacts` |
| Container / host metrics | Docker + System integrations | `metrics-docker.*`, `metrics-system.*` |

**Built-in Elastic Agent integrations in use:** System, File Integrity Monitoring,
Osquery Manager, Docker, and Custom Logs (Falco / Zeek / INetSim) — all Fleet-managed.

### Not available on OrbStack (kernel/topology limits)

| Capability | Why | How to get it |
|---|---|---|
| Elastic **Auditd** integration | The OrbStack kernel is built without `CONFIG_AUDIT` (`audit not supported by kernel`). Falco's eBPF provides the syscall pillar instead. | Enable with `ADD_AUDITD=1 ./scripts/bootstrap-fleet.sh` on a kernel that has the audit subsystem. |
| Elastic **Defend** (endpoint) | Runs as a host systemd service; it cannot run as a service inside the collector container. | Install a host agent inside a dedicated sandbox VM, then `ADD_DEFEND=1 ./scripts/bootstrap-fleet.sh`. |

## Prerequisites

- macOS with [OrbStack](https://orbstack.dev) (shared Docker engine).
- ≥ 12 GB assigned to the OrbStack Docker VM recommended (the full stack is heavy;
  ES heap is capped at `ES_MEM` in `.env`).
- `python3` and `curl` on the host (used by the Fleet bootstrap script).

## Usage

1. **Edit `.env`** and change the default passwords / encryption keys.
2. **Start the management plane** (on the macOS host, from the repo dir):

```bash
./start-elk.sh
```

   This launches ES/Kibana/Fleet, creates the `malware-analysis` policy with all
   integrations, and writes the enrollment token into `.env`.

3. **Start the detonation plane** (enter the sandbox VM, then run):

```bash
orb                 # enter the running Linux machine
cd ~/OrbStack-ELK
./start-sandbox.sh
```

4. **Detonate a sample** inside the isolated victim:

```bash
docker cp ./sample.elf malware-sandbox:/tmp/
docker exec -it malware-sandbox bash
# run the sample; watch telemetry stream into Kibana
```

5. **Capture memory artifacts** on demand:

```bash
./scripts/memory-capture.sh <pid|process-name> [--core]
```

6. **View data** in Kibana → Discover (`logs-*`, `metrics-*`) and Security apps.

## Security / isolation notes

- The sandbox is unprivileged (`cap_drop: ALL`, `no-new-privileges`) and on an
  `internal` network with no path to the real internet — only the sinkhole.
- The Elastic Agent is deliberately kept **off** `malware-net`.
- **Shared-kernel caveat:** OrbStack runs one Linux kernel for all containers.
  A container escape from a *real* sample would reach that kernel. For
  higher-assurance isolation, run the sandbox in a dedicated OrbStack VM (its own
  kernel) or a microVM (Kata/Firecracker) and point a host-installed agent at it.
- **Elastic Defend caveat:** Elastic Defend (endpoint) is designed to run as a
  host service, not inside a container. The bootstrap adds it best-effort; if it
  does not activate in this container topology, the auditd + FIM + Falco + Zeek
  pipeline still covers all six behavioural pillars. To get full Defend telemetry,
  install a host agent inside the sandbox VM.
- TLS is disabled on the ES/Kibana HTTP layer for a self-contained local lab
  (auth is still required). Do not expose these ports beyond localhost.

## Operational notes

- **Recreate Zeek after recreating the sandbox.** Zeek shares the sandbox's
  network namespace (`network_mode: service:malware-sandbox`), so if you rebuild
  or recreate `malware-sandbox`, run `docker compose -f compose.sandbox.yml up -d
  --force-recreate zeek` so it re-attaches to the new namespace.
- Zeek runs with `ignore_checksums=T` because virtual/container NICs offload
  checksums (otherwise only `conn.log`/`weird.log` appear, no dns/http/ssl).
- Memory: `.env` caps ES heap at `ES_MEM`. The whole stack is heavy for an 8 GB
  Docker VM; 12–16 GB is recommended.

## Files

| Path | Purpose |
|---|---|
| `.env` | versions, credentials, ports, enrollment token |
| `compose.elk.yml` | Elasticsearch + Kibana + Fleet Server |
| `compose.sandbox.yml` | agent + sandbox + sinkhole + Falco + Zeek |
| `config/kibana/kibana.yml` | Fleet policies + integrations (declarative) |
| `config/falco/falco.yaml` | Falco (modern eBPF, JSON output) |
| `config/zeek/local.zeek` | Zeek JSON logging + analyzers |
| `config/inetsim/inetsim.conf` | sinkhole services |
| `scripts/bootstrap-fleet.sh` | Fleet setup + enrollment token |
| `scripts/memory-capture.sh` | on-demand memory artifacts |
