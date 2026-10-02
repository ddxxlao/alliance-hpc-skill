# Sourced by install-sglang.sh and by every SGLang job, so build and run use the same stack.
# Must be sourced BEFORE activating ~/venvs/sglang:
#  - arrow provides pyarrow (pip install sglang fails without it)
#  - cuda/12.9 matches the wheelhouse torch (torch.version.cuda == 12.9) and sets CUDA_HOME,
#    which deep_gemm / flashinfer JIT need at import time (AssertionError in find_cuda_home otherwise)
module --force purge >/dev/null 2>&1 || true
module load StdEnv/2023 gcc python/3.12 arrow cuda/12.9
