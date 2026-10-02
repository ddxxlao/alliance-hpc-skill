#!/bin/bash
# Launch an SGLang OpenAI-compatible server inside the job, smoke-test it, then benchmark it.
# Submit:  hpc submit <cluster> templates/sglang-server.sbatch --export=ALL,MODEL=$(hpc model-path <cluster> <repo>)
# Optional env: TP (default 1), NUM_PROMPTS (default 200), KEEP_SERVING=1 to keep the server up
# until the time limit (for interactive tests via `ssh -L`; see SKILL.md).
#SBATCH --job-name=sglang-server
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
PORT=$((30000 + SLURM_JOB_ID % 10000))
echo "job=$SLURM_JOB_ID host=$(hostname) port=$PORT model=$MODEL"
nvidia-smi -L

python -m sglang.launch_server --model-path "$MODEL" --tp "${TP:-1}" \
  --host 127.0.0.1 --port "$PORT" > "$SCRATCH/jobs/sglang-server-$SLURM_JOB_ID.server.log" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT

for i in $(seq 1 180); do            # model load + CUDA graph capture can take minutes
  curl -sf "http://127.0.0.1:$PORT/health" >/dev/null && break
  kill -0 $SERVER 2>/dev/null || { echo "server died:"; tail -50 "$SCRATCH/jobs/sglang-server-$SLURM_JOB_ID.server.log"; exit 1; }
  sleep 5
done
curl -sf "http://127.0.0.1:$PORT/health" >/dev/null || { echo "server not healthy after 15 min"; exit 1; }
echo "server ready after ~$((i * 5))s"

curl -s "http://127.0.0.1:$PORT/v1/chat/completions" -H 'Content-Type: application/json' \
  -d '{"model":"default","messages":[{"role":"user","content":"Say hello in five words."}],"max_tokens":32,"temperature":0}'
echo

# random-ids = random token ids, needs no download ('random' fetches ShareGPT from HF and fails offline)
python -m sglang.bench_serving --backend sglang --host 127.0.0.1 --port "$PORT" \
  --dataset-name random-ids --random-input-len 512 --random-output-len 128 \
  --num-prompts "${NUM_PROMPTS:-200}"

if [ "${KEEP_SERVING:-0}" = 1 ]; then echo "KEEP_SERVING=1: serving on $(hostname):$PORT until time limit"; wait $SERVER; fi
