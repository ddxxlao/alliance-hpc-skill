---
name: alliance-hpc
description: Run GPU work (especially SGLang / LLM inference) on the user's Digital Research Alliance of Canada Slurm clusters — nibi, fir, rorqual, narval, trillium-gpu — under the allocation and username set in the skill's config.env. Use whenever a task mentions Alliance / Compute Canada / DRAC, one of those cluster names, Slurm/sbatch jobs, H100/A100 GPUs for experiments, or setting up an inference environment or downloading model weights on a cluster. Covers the MFA/SSH session rule, per-cluster differences (offline compute nodes, Trillium read-only HOME, full file quotas), the `hpc` helper script, and tested SGLang job templates.
---

# Alliance HPC (Slurm GPU clusters)

Everything here goes through `scripts/hpc` (run it by absolute path:
`~/.claude/skills/alliance-hpc/scripts/hpc`). Cluster facts, storage paths and quotas are in
`reference/clusters.md`. Read it before choosing a cluster or a storage location.

The user's Alliance username and Slurm account are in `config.env` (`HPC_USER`, `HPC_ACCOUNT`).
If `hpc` says `HPC_USER` is unset, ask the user for their username and fill it in. Below,
`$HPC_ACCOUNT` means that account (e.g. `def-baochun`).

## Rule 0: the user owns authentication

- Every cluster enforces Duo MFA. Agents **cannot** log in.
- The user opens a session by running `ssh <cluster>` in a real terminal. A Claude `!` shell has no
  TTY, so Duo fails there. That one session is shared through an SSH ControlMaster for 8h.
- Always start with `hpc check`. If a cluster shows DEAD, stop and ask the user to run
  `ssh <cluster>` in their terminal, then continue.
- Never loop or retry connections, never try passwords, and never ask for Duo codes. Failed
  attempts are logged against the account.
- Never run raw `ssh <cluster> ...` or `rsync`/`scp` from an agent: if the ControlMaster socket died, ssh silently
  opens a NEW connection, which hits Duo and is logged as a failed login. Go through `hpc` (its ssh is
  multiplex-only: `-o ControlMaster=no -o ProxyCommand=/usr/bin/false`, so a dead socket fails instantly).
  If raw ssh is unavoidable, pass those same options.
- Batch remote work into few calls: one `hpc run` with a multi-line script beats many small ones.

## Which cluster?

| Need | Use |
| --- | --- |
| Develop or debug, install things, anything that may fetch from the internet at runtime | `nibi` or `fir`: H100 80GB, compute nodes have internet |
| Production H100 runs with everything pre-staged | `rorqual` (no internet on compute) or any of the above |
| Model fits in 40GB, or the H100 queues are long | `narval`: A100 40GB, no internet on compute, models go in `$SCRATCH` |
| 4×H100 tensor parallel on one node, lots of RAM | `trillium-gpu`: only 1 or 4 GPUs per node, and see the Trillium rules below |
| Small model, want to start fast | request a MIG slice, e.g. `--gpus-per-node=nvidia_h100_80gb_hbm3_3g.40gb:1` |

`killarney`, `vulcan` and `tamia` accept SSH but reject `def-*` accounts (tested with `def-baochun`).
Do not use them unless the user has an `aip-*` or similar allocation there.

Each cluster has its **own** filesystems. An env or model on one cluster does not exist on another.

## Workflow for an inference project

```bash
H=~/.claude/skills/alliance-hpc/scripts/hpc
$H check                                   # 1. sessions alive?
$H setup-env nibi                          # 2. once per cluster: build ~/venvs/sglang (30-40 min, runs in background)
$H setup-env nibi --status                 #    poll every few minutes, not seconds. Wait for "state: DONE"
$H fetch-model nibi Qwen/Qwen2.5-7B-Instruct         # 3. download weights ON THE LOGIN NODE
$H fetch-model nibi Qwen/Qwen2.5-7B-Instruct --status
M=$($H model-path nibi Qwen/Qwen2.5-7B-Instruct)
$H run nibi 'mkdir -p $SCRATCH/jobs'      # 4. ship code ($SCRATCH is /scratch/<user> on all five clusters)
$H put nibi ~/.claude/skills/alliance-hpc/templates/sglang_offline.py '$SCRATCH/jobs/'   # hpc expands a quoted $SCRATCH
$H submit nibi ~/.claude/skills/alliance-hpc/templates/sglang-offline.sbatch --export=ALL,MODEL=$M   # 5. prints the job id
$H status nibi <jobid>                     # 6. PENDING/RUNNING/COMPLETED + reason
$H log nibi <jobid>                        # 7. output ($SCRATCH/jobs/<name>-<jobid>.out)
```

What `hpc submit` does:
- copies the sbatch file to `$SCRATCH/jobs/` and submits it from there, so logs land in `$SCRATCH/jobs`
- always adds `--account=$HPC_ACCOUNT`
- adds the cluster's default `--gpus-per-node` (`h100:1`, `a100:1`, or `1` on trillium) unless
  you pass your own
- passes any extra sbatch flags straight through, e.g. `--time=02:00:00` or
  `--gpus-per-node=h100:2 --export=ALL,MODEL=$M,TP=2`

Templates (in `templates/`, tested on nibi H100):
- `sglang-offline.sbatch` + `sglang_offline.py`: offline `sgl.Engine` batch generation that
  reports tok/s. Start real batch jobs from here.
- `sglang-server.sbatch`: runs `sglang.launch_server` inside the job, waits for `/health`, sends
  one chat request, then runs `sglang.bench_serving`. Set `KEEP_SERVING=1` to keep it serving.
  Then from the Mac: `ssh -L 30000:<node>:<port> <cluster>`. The log prints the node and port.

When writing your own job script, copy the three `source` lines from a template. They load the
exact module stack the venv was built with, activate the venv, and point every cache to `$SCRATCH`
with HF offline mode on.

## Offline compute nodes (rorqual, narval, trillium)

Compute nodes cannot reach the internet. Do all downloads **on the login node** (`hpc fetch-model`,
`hpc run '... pip install ...'`). Login and compute nodes of the same cluster share
`/home`, `/project` and `/scratch`, so nothing needs to be pushed to compute nodes afterwards.
Jobs run with `HF_HUB_OFFLINE=1`, so any file that was not pre-downloaded fails immediately
instead of hanging.

- Gated models (Llama etc.) need an HF token on the cluster. Ask the user to run `hf auth login`
  there themselves. Never put tokens in scripts, logs or this skill.
- For very large downloads, the login node may kill long processes. Prefer running them on nibi or
  fir, or as a CPU job on nibi or fir (those compute nodes are online), then `rsync` between clusters
  only if you must.

## Hard rules (each one has already bitten)

1. **No compute on login nodes.** Installs and downloads are fine. Inference and benchmarks go
   through `sbatch`/`salloc`.
2. **`module load` before activating the venv, and never inside a pipe.** `module load x | tail`
   runs in a subshell and silently loads nothing. `pip install sglang` needs the `arrow` module,
   otherwise it fails on `pyarrow-noinstall`. `~/venvs/sglang-modules.sh` handles this: always
   source it.
3. **Venvs live in HOME, never in `/project`.** Group project file quotas are nearly or completely
   full (nibi 437K/500K, narval 500K/500K). Weights (few, large files) may go in project, except on
   narval.
4. **Never run two installs into the same venv.** An interrupted local command does not stop the
   remote process. Check `hpc setup-env <c> --status` first.
5. **SGLang jobs need `cuda/12.9` loaded and `TVM_FFI_GPU_BACKEND=cuda`.** Both are already in
   `sglang-modules.sh` / `sglang-job-env.sh`.
   - Without the cuda module, `import deep_gemm` fails with `AssertionError` in
     `find_cuda_home`.
   - Without the env var, the SGLang JIT kernels crash with `Could not detect ROCm GPU
     architecture`, because the Nibi H100 node image also ships `/opt/rocm` and `hipcc`.
   - First startup JIT-compiles kernels and captures CUDA graphs (~2-3 min for a 0.5B model).
     Later jobs reuse `$SCRATCH/.cache`.
6. **Trillium:**
   - Only `--gpus-per-node=1` or `4` is allowed, and the minimum `--time` is 15 min.
   - HOME and `/project` are **read-only** on compute nodes, so outputs and caches must go to
     `$SCRATCH`. The templates already do this.
   - Submit from `$SCRATCH` (hpc submit does).
7. **Opportunistic allocation:** a default `def-*` allocation has no reserved GPUs.
   - Keep `--time` realistic; shorter jobs backfill sooner.
   - If a job pends, read the reason with `hpc status`, and consider a MIG slice or another cluster.
   - Don't poll faster than every minute or two.
8. Don't touch other members' dirs in `/project/$HPC_ACCOUNT/`. Personal space is
   `/project/$HPC_ACCOUNT/$USER`.
9. Report job results honestly. A job is verified only with state COMPLETED, exit code `0:0`, and
   the expected output present in the log.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| `hpc: no live SSH session` | The user must run `ssh <cluster>` in a terminal. Do not retry. |
| `Invalid account` | Use `--account=$HPC_ACCOUNT` (hpc adds it), and make sure the cluster is one of the five usable ones. |
| Job PENDING for long | Run `hpc status` to see the reason. Options: shorter `--time`, a MIG slice, or another cluster. |
| `ModuleNotFoundError` in a job | The job didn't source `sglang-modules.sh` + venv, or the install isn't DONE. |
| `OSError: ... read-only file system` | A cache or output is going to HOME or project on Trillium. Source `sglang-job-env.sh` and write to `$SCRATCH`. |
| HF `LocalEntryNotFoundError` / offline error | The weights weren't fully downloaded. Check `hpc fetch-model <c> <repo> --status`. |
| `AssertionError` in `deep_gemm ... find_cuda_home` | The `cuda/12.9` module is not loaded. Source `~/venvs/sglang-modules.sh` (re-run `hpc setup-env` to refresh the remote copies). |
| `Could not detect ROCm GPU architecture` | `TVM_FFI_GPU_BACKEND=cuda` is missing. Source `~/venvs/sglang-job-env.sh`. |
| `bench_serving` `LocalEntryNotFoundError` | `--dataset-name random` downloads ShareGPT. Use `random-ids`, or pre-download the dataset on the login node. |
| CUDA OOM | Use a smaller model or MIG → full GPU, or lower `--mem-fraction-static`, or TP across more GPUs. |
