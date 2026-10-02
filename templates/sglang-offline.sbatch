#!/bin/bash
# Offline batch inference with the SGLang engine.
# Submit:  hpc put <cluster> templates/sglang_offline.py '$SCRATCH/jobs/'   (once; adjust path as needed)
#          hpc submit <cluster> templates/sglang-offline.sbatch --export=ALL,MODEL=$(hpc model-path <cluster> <repo>)
# hpc submit adds --account=$HPC_ACCOUNT and the cluster's default --gpus-per-node
# (h100:1 / a100:1 / 1 on trillium). For tensor parallel pass --gpus-per-node=h100:N and TP=N.
#SBATCH --job-name=sglang-offline
#SBATCH --time=00:30:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --output=%x-%j.out
set -euo pipefail
: "${MODEL:?pass --export=ALL,MODEL=/abs/path/to/weights}"
source ~/venvs/sglang-modules.sh
source ~/venvs/sglang/bin/activate
source ~/venvs/sglang-job-env.sh
echo "job=$SLURM_JOB_ID host=$(hostname) account=$SLURM_JOB_ACCOUNT model=$MODEL"
nvidia-smi -L
python -u "$SCRATCH/jobs/sglang_offline.py" --model "$MODEL" --tp "${TP:-1}"
