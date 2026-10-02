# alliance-hpc: a Claude Code skill for Alliance (DRAC) GPU clusters

Lets Claude Code run Slurm GPU jobs (especially SGLang / LLM inference) on nibi, fir, rorqual,
narval and trillium-gpu without ever handling your Duo MFA. You log in once in a terminal; Claude
reuses that SSH session for 8 hours through the `scripts/hpc` helper.

Tested on 2026-09-26 with the `def-baochun` allocation (macOS client).

## Install

1. Clone into the skills folder (the path matters: SKILL.md and the templates refer to
   `~/.claude/skills/alliance-hpc/scripts/hpc`):
   ```bash
   git clone https://github.com/ddxxlao/alliance-hpc-skill ~/.claude/skills/alliance-hpc
   ```
2. Edit `config.env`:
   ```bash
   HPC_USER=${HPC_USER:-jdoe}               # your Alliance (CCDB) username
   HPC_ACCOUNT=${HPC_ACCOUNT:-def-baochun}  # your Slurm allocation
   ```
3. Register your SSH public key in CCDB (ccdb.alliancecan.ca → My Account → SSH Keys).
4. Add one block per cluster to `~/.ssh/config`, and create the
   socket dir with `mkdir -p ~/.ssh/cm`:
   ```
   Host nibi
     HostName nibi.alliancecan.ca
     User jdoe
     IdentityFile ~/.ssh/id_ed25519
     IdentitiesOnly yes
     ControlMaster auto
     ControlPath ~/.ssh/cm/%r@%h:%p
     ControlPersist 8h
     ServerAliveInterval 30
     ServerAliveCountMax 3
   ```
   Repeat with `Host fir` / `fir.alliancecan.ca`, `rorqual` / `rorqual.alliancecan.ca`,
   `narval` / `narval.alliancecan.ca`, and `trillium-gpu` / `trillium-gpu.scinet.utoronto.ca`.
   The aliases must be exactly these names.

## Daily use

1. In a real terminal (not a Claude `!` shell), run `ssh nibi` (or whichever cluster) and approve
   the Duo push. Leave it; the session is shared for 8h.
2. Ask Claude for GPU work, e.g. "run Qwen2.5-7B with SGLang on nibi and report throughput".
   Claude runs `hpc check` first and asks you to log in again if the session has expired.

First time on each cluster, Claude runs `hpc setup-env <cluster>` to build `~/venvs/sglang`
(30-40 min, in the background).

## Contents

| Path | What |
| --- | --- |
| `SKILL.md` | Instructions Claude follows: auth rules, cluster choice, workflow, hard-won pitfalls |
| `config.env` | Your username and account |
| `scripts/hpc` | Helper: `check`, `run`, `put`, `get`, `setup-env`, `fetch-model`, `submit`, `status`, `log`, `cancel` |
| `scripts/remote/` | Files `setup-env` uploads to `~/venvs/` on the cluster (module stack, job env, installer) |
| `templates/` | Tested sbatch templates: SGLang offline engine and SGLang server + benchmark |
| `reference/clusters.md` | Per-cluster GPUs, internet access, storage, quotas, software versions, host keys |

Notes:
- `killarney`, `vulcan` and `tamia` reject `def-*` accounts, so the skill refuses them.
- Narval models go to `$SCRATCH` because the `def-baochun` project file quota there is full. If
  your group has room, you can change `model_root` in `scripts/hpc`.
- Quota numbers and versions in `reference/clusters.md` are snapshots from 2026-09-26.
