"""Minimal SGLang offline-engine run: load a local model, generate for a few prompts, report throughput.
Copy and adapt for real workloads (read prompts from a file, write outputs to $SCRATCH)."""
import argparse, json, time

import sglang as sgl


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True, help="local weights dir (hpc model-path ...)")
    ap.add_argument("--tp", type=int, default=1)
    ap.add_argument("--num-prompts", type=int, default=64)
    ap.add_argument("--max-new-tokens", type=int, default=128)
    args = ap.parse_args()

    llm = sgl.Engine(model_path=args.model, tp_size=args.tp)
    base = ["Explain what a GPU is in one paragraph.", "Write a haiku about Toronto.",
            "List three uses of Slurm.", "What is 17 * 23? Answer briefly."]
    prompts = [base[i % len(base)] for i in range(args.num_prompts)]
    params = {"temperature": 0.0, "max_new_tokens": args.max_new_tokens}

    t0 = time.time()
    outs = llm.generate(prompts, params)
    dt = time.time() - t0
    gen = sum(o["meta_info"]["completion_tokens"] for o in outs)
    print("sample:", json.dumps(outs[0]["text"][:200]))
    print(f"prompts={len(prompts)} completion_tokens={gen} seconds={dt:.2f} tok/s={gen / dt:.1f}")
    llm.shutdown()


if __name__ == "__main__":
    main()
