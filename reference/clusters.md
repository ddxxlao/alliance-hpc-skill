# Alliance clusters (tested with allocation `def-baochun`)

All facts below were verified on 2026-09-26 with the `def-baochun` allocation, by logging in and
running real GPU jobs. Queue state, quotas and software versions change, so re-check with `hpc run <cluster> '...'` when a detail matters.

## Usable clusters

| Alias (`ssh <alias>`) | Login host | GPU for `--gpus-per-node` | Compute-node internet | Model root used by `hpc fetch-model` |
| --- | --- | --- | --- | --- |
| `nibi` | nibi.alliancecan.ca | `h100:1` (H100 80GB). Also offers MIG slices `nvidia_h100_80gb_hbm3_{1g.10gb,2g.20gb,3g.40gb}`, plus `a100`, `t4` and `mi300a` (AMD/ROCm, not CUDA). | yes | `/project/$HPC_ACCOUNT/$USER/models` |
| `fir` | fir.alliancecan.ca | `h100:1`, plus the same H100 MIG slices | yes | `/project/$HPC_ACCOUNT/$USER/models` (the dir is created on first fetch) |
| `rorqual` | rorqual.alliancecan.ca | `h100:1`, plus the same H100 MIG slices | **no** | `/project/$HPC_ACCOUNT/$USER/models` |
| `narval` | narval.alliancecan.ca | `a100:1` (A100-SXM4 **40GB**), plus MIG slices `a100_{1g.5gb,2g.10gb,3g.20gb,4g.20gb}` | **no** | `$SCRATCH/models`, because the project file quota is full (500K/500K) |
| `trillium-gpu` | trillium-gpu.scinet.utoronto.ca | `1` or `4` only, with no type name. Gives an H100 80GB; H200 and B200 partitions exist but have not been tested. | **no** | `/project/$HPC_ACCOUNT/$USER/models` |

Every login node has internet access. Download models and install packages there, not in jobs.

## Verified smoke jobs

All five ran `nvidia-smi` with `--account=def-baochun` and finished COMPLETED 0:0
(nibi, fir, rorqual and trillium-gpu on H100; narval on A100 40GB).

Queue waits on 2026-09-26 were seconds. That is opportunistic capacity with no guarantee.

## Not usable

`killarney`, `vulcan` and `tamia` all have `Host` entries and accept SSH. However, `sbatch` returns
`Invalid account or account/partition combination` for `def-baochun` (and likely any `def-*` account). Using them would need a
separate allocation (e.g. an AI-program `aip-*` account) requested by the PI.

## Storage (per cluster, NOT shared across clusters)

The login and compute nodes of one cluster see the same `/home`, `/project` and `/scratch`. A file
downloaded on the login node is therefore already visible to jobs on that cluster, and nothing needs
to be pushed. Moving data between clusters needs `rsync` or Globus.

| Area | Use for | Caveats |
| --- | --- | --- |
| `~` (HOME, ~50GB / 500K files; Trillium 100GB) | venvs (`~/venvs/sglang`), scripts | Network FS: installs with many small files are slow (30-40 min for SGLang). On **Trillium compute nodes HOME is read-only**. |
| `/project/$HPC_ACCOUNT/$USER` (group share) | model weights, results to keep | File-count quotas are shared by the whole group. For `def-baochun` (2026-09-26): Nibi 437K/500K, **Narval 500K/500K (full)**. Check yours with `diskusage_report`. Never put venvs or pip caches here. Read-only on Trillium compute nodes. |
| `$SCRATCH` (`/scratch/$USER`, TBs) | job outputs, logs (`$SCRATCH/jobs`), caches, big temporary data | Not backed up. Files unused for a while get purged. |
| `$SLURM_TMPDIR` | fast node-local disk during a job | Deleted when the job ends. |

Convention: one directory per member under `/project/$HPC_ACCOUNT/` (create yours with
`mkdir -m 2700 /project/$HPC_ACCOUNT/$USER` if it does not exist).

## Slurm notes

- Pass the plain account (`--account=def-xxx`). Slurm maps it to `def-xxx_gpu` or `def-xxx_cpu` by itself
  on Nibi, Fir, Rorqual and Narval. (For the baochun group: `rrg-baochun` is inactive, use `def-baochun`.)
- Trillium rules:
  - Only `--gpus-per-node=1` or `4` is allowed.
  - The minimum time is 15 min; the default is 15 min and triggers a warning.
  - `--mem` is ignored; 1 GPU gives a quarter node (24 cores, ~187GB RAM).
  - Submit from `$SCRATCH`.
- MIG slices usually start sooner than full GPUs when the model fits in the slice memory.
- Requesting several GPUs does not make one process multi-GPU. With SGLang, pass
  `--tp <n>` (tensor parallel) or `--dp <n>`, and request that many GPUs on one node.

## Software stack (identical CVMFS stack on all five clusters)

- Modules: `StdEnv/2023 gcc python/3.12 arrow`. `arrow` must be loaded **before** activating the
  venv, otherwise `pip install sglang` fails on a dummy `pyarrow-noinstall` wheel.
- Wheelhouse (`pip install --no-index`) offers torch up to 2.14.0 and sglang 0.5.15.post1 for
  cp312. The resolver installs **torch 2.11.0 (CUDA 12.9)** together with sglang 0.5.15.post1.
  Verified on nibi 2026-09-26.
- Runtime needs `cuda/12.9` (CUDA_HOME for deep_gemm/JIT) and `TVM_FFI_GPU_BACKEND=cuda` (GPU
  nodes have /opt/rocm). Both are in the remote helper files.
- Reference numbers: Qwen2.5-0.5B-Instruct on one nibi H100 with the offline engine ran 64
  prompts × 128 tokens at ~770 tok/s. Most of the ~3.5 min job was startup:
  JIT compilation and CUDA graph capture.
- Server template: `bench_serving` with `random-ids`, 200 prompts, 512 input and
  128 output tokens.
  - Output throughput ~3.5k tok/s; total throughput ~17.8k tok/s.
  - Median TTFT ~490 ms.
  - All 200 requests OK.
- Never pipe `module load` into another command (`module load x | tail`). The pipe runs it in a
  subshell, so the modules silently do not load.

## Access / MFA

- Your SSH public key must be registered in CCDB (ccdb.alliancecan.ca → My Account → SSH Keys).
- Duo MFA is mandatory on every new connection. `~/.ssh/config` gives each alias
  `ControlMaster auto`, `ControlPath ~/.ssh/cm/%r@%h:%p` and `ControlPersist 8h`, so one Duo
  approval from the user serves ~8h of agent commands (see README.md for the config block).
- A Claude `!` shell has no TTY, so Duo fails there. The user must use a real terminal.

## Host key fingerprints (ED25519, seen 2026-09-26)

| Alias | Fingerprint |
| --- | --- |
| nibi | SHA256:iDzUuOogiUaSq47xp/v4IAegE53uLP5VtiP0WFXikRc |
| fir | SHA256:NJgHnZFzGX0zYyUwCMUdWccvfCaTgKmZKzPaqL8VNM8 |
| rorqual | SHA256:Xe4zQTOysm5MbI2Euuo5ZKbrnTsqMUgUBRorb9MfYoU |
| narval | SHA256:pTKCWpDC142truNtohGm10+lB8gVyrp3Daz4iR5tT1M |
| trillium-gpu | SHA256:ZdxQWOLHPQb11qPxHh2Vq+trSULZA1+rvTU6pePelSc |
| killarney | SHA256:M8R87mGQthsmxASCufmSZ/Q0uPY+7Nm+nizC5RP6LPg |
| vulcan | SHA256:QWK/6JdB3DAZmEmIZ6Vp5xXbFdEvL2uWaFvb53RF7lM |
| tamia | SHA256:QuJnAQCqMWr1qYJfV16pRLTaZmGHBgwgHFZHB+hkCTI |
