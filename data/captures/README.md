# Week 0 Capture Session — Real Telemetry Artifacts

Captured to ground the event schema, ingestion adapters, and failure
taxonomy in **real formats** rather than assumed ones.

Everything in `scrubbed/` is committed. `raw/` is gitignored.
Scrubber: `scripts/scrub_captures.sh` (idempotent, format-preserving).

## Capture environment

| Field | Value |
|---|---|
| Date | 2026-09-16 |
| Platform | Lightning AI Studio (containerized, host kernel shared) |
| GPU | 1× NVIDIA A100-SXM4-40GB |
| Driver | 570.148.08 (Open Kernel Module) |
| CUDA | 12.8 |
| OS | Ubuntu 24.04.4 LTS, kernel 6.8.0-60-generic |
| DCGM | 4.1.1 (`dcgm-exporter:4.1.1-4.0.4`, `cloud-native/dcgm:4.1.1-1`) |
| Interconnect | PCIe only — NVLink present but all links inactive |
| NIC | mlx5_0 (Mellanox), PHB to GPU |

`dmesg` required `sudo sysctl -w kernel.dmesg_restrict=0` (does not
persist across Studio restarts).

## Artifacts

| File | What it grounds |
|---|---|
| `dcgm_exporter_metrics.txt` | Prometheus exposition format, label set |
| `dcgm_field_reference.txt` | Full DCGM field-ID catalogue (authoritative) |
| `dcgmi_diag_r1.json` | Diagnostic result schema, typed error objects |
| `dcgmi_discovery.txt` | Entity enumeration format |
| `dcgm_throttle_trace.txt` | 4-min load test, DCGM side, 2s interval |
| `smi_throttle_trace.csv` | Same window, nvidia-smi side |
| `nvidia_smi_q.txt` | Full `-q` field tree |
| `nvidia_smi_topo.txt` | Topology matrix (1×1 — see limitations) |
| `nvlink_status.txt` | NVLink state (inactive) |
| `ecc_baseline.txt` | ECC field structure, healthy baseline |
| `dmesg_nvrm.txt` | Kernel NVRM line formats (no Xid — healthy GPU) |
| `kmsg_sample.txt` | `/dev/kmsg` structured format |
| `proc_nvidia_gpus.txt` | `/proc/driver/nvidia/gpus/*/information` |
| `environment.txt` | Host/driver metadata |

## Findings that changed the design

### 1. `DCGM_FI_DEV_XID_ERRORS` is a gauge of the *last* Xid, not a counter
Help text: "Value of the last XID error encountered." It persists after
recovery and cannot count events. Bursts within one scrape interval
collapse to a single observation.

**Consequence:** `dmesg` / `/dev/kmsg` is the authoritative Xid event
source. DCGM corroborates but cannot detect. The `err_code` / `err_msg`
labels do give free code→meaning decoding.

### 2. dcgm-exporter drops unsupported fields silently
Requested 43 fields in a custom counters file, got 32. No warning, no
error, no log line.

**Consequence:** a startup capability probe is required — scrape
`/metrics`, diff against the required-field list, and mark affected
failure classes as *unassessable* rather than *healthy*.

### 3. Violation counters can read 0 while the condition is active
During the load test `CLOCK_THROTTLE_REASONS` reported `0x4` (SwPowerCap)
for 119 consecutive samples while `POWER_VIOLATION`,
`THERMAL_VIOLATION` and `BOARD_LIMIT_VIOLATION` all stayed at `0`.
The counters require violation accounting to be enabled; unpopulated
reads as zero.

**Consequence:** the event schema needs three states, not two —
`MEASURED_PRESENT`, `MEASURED_ABSENT`, `NOT_MEASURED`. Cross-checking
the bitmask against the counters detects the third case and is itself
a contradiction rule for the causal KB.

### 4. `Hostname` label is the container ID, and the label set varies
Observed `Hostname="7e6f00cf349d"` — the dcgm-exporter container, not
the host. `DCGM_FI_DRIVER_VERSION` appeared with the default counters
file and was absent with the custom one.

**Consequence:** key entities on `UUID` + `pci_bus_id`. Never require
`Hostname` or any optional label.

### 5. ECC is per-location; remapped rows are a degradation ladder
Fields 310–345 split volatile/aggregate across L1, L2, device, register,
texture, shared, CBU and SRAM. SRAM ECC (Xid 94, contained) and DRAM
double-bit (Xid 48) need different remediation.

Fields 385–389 expose `remap_rows_avail_{max,high,partial,low,none}` —
a monotonic descent, not a binary. This is a precursor signal and feeds
lemon-node detection directly.

### 6. NVLink error taxonomy is far more granular than the exporter suggests
Fields 1200–1215 distinguish `rcv_err` from `rcv_remote_err` (local vs
peer fault), `link_recovery_successful` from `link_recovery_failed`
(transient vs persistent), and expose `symbol_ber` as a continuous
degradation signal. `buffer_overrun_err` indicates congestion, not
hardware failure.

Per-link field indices are **non-contiguous** (flit CRC exists for
l0–l5 then l12–l14). Parsers must not loop `0..N`.

**Consequence:** "NVLink fault" is too coarse for a single taxonomy
class. Recovery-succeeded is a *contradicting* signal for persistent
hardware-fault hypotheses.

### 7. dcgm-exporter cannot run diagnostics
It runs DCGM embedded, with no `nv-hostengine` listening and no plugin
directory. `dcgmi` against it fails with a connection error.
The `cloud-native/dcgm` image is required for `dcgmi diag`.

Separately, diagnostic results are readable as **fields 350–362**
(`pcie_test_result`, `diag_status`, …), so the agent can read results
without shelling out and parsing JSON.

### 8. `diag status: Fail` does not mean hardware failure
The r1 run failed on `error_category: 8, error_id: 29` — persistence
mode disabled. A deployment misconfiguration, not a fault.

**Consequence:** read `error_category` and `error_severity`, never
`status` alone.

### 9. Kernel logs identify GPUs by packed PCI address
`[drm] [nvidia-drm] [GPU ID 0x00000600] Loading driver` → `0000:06:00.0`.
The dmesg parser must decode this to join kernel events to DCGM entities.

### 10. Instantaneous power draw exceeds the enforced cap
Observed 437.47 W against a 400 W limit. `power.draw > power.limit` is
not by itself evidence of a fault.

## Load test result

4-minute fp16 GEMM loop (16384², 6900 iterations): throttle reasons 0x1 GpuIdle → 0x0 none → 0x4 SwPowerCap → 0x1
temperature 32 °C → 76 °C
power 48 W → 437 W (cap 400 W)
SM clock 210 → 1410 MHz   
A complete idle→active→throttle→cooldown transition. This is the
grounding trace for the thermal/power failure class.

## Limitations of this capture

Not obtainable on this platform:

- **Real Xid line format** — healthy GPU, no Xid fired. Parser must be
  written from NVIDIA documentation and public issue reports, then
  validated against real lines later.
- **Multi-GPU topology** — `topo -m` is 1×1. No peer relationships, so
  Layer 1 topology design has no real example to check against.
- **NVLink error fields** — links inactive, so DCGM does not enumerate
  them ("Not collecting NvLink metrics; no switches to monitor").
- **NCCL debug traces** — single GPU.
- **NVSwitch / fabric manager** — no switches present.

These require a 2+ GPU host with active NVLink and are deferred to a
follow-up capture session.
