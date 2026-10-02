# Sourced inside every SGLang job (after the venv is activated).
# - Compute nodes on rorqual/narval/trillium have no internet: force HF offline so a missing
#   file fails fast instead of hanging on a download.
# - Trillium compute nodes mount HOME and /project read-only, so every cache SGLang, Triton,
#   FlashInfer or torch.compile writes goes to $SCRATCH. Keeping the caches there (not in
#   $SLURM_TMPDIR) lets later jobs reuse compiled kernels.
export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1
export XDG_CACHE_HOME=$SCRATCH/.cache
export HF_HOME=$XDG_CACHE_HOME/huggingface
export TRITON_CACHE_DIR=$XDG_CACHE_HOME/triton
export TORCHINDUCTOR_CACHE_DIR=$XDG_CACHE_HOME/torchinductor
export FLASHINFER_WORKSPACE_BASE=$XDG_CACHE_HOME
export OUTLINES_CACHE_DIR=$XDG_CACHE_HOME/outlines
export TVM_FFI_CACHE_DIR=$XDG_CACHE_HOME/tvm-ffi   # ignores XDG; default ~/.cache is read-only on Trillium
# The Nibi (and possibly other) GPU node images ship /opt/rocm + hipcc even on NVIDIA nodes, so
# tvm_ffi (SGLang JIT kernels) auto-detects "hip" and dies with "Could not detect ROCm GPU
# architecture". Force CUDA. Remove this line only for the AMD MI300A nodes.
export TVM_FFI_GPU_BACKEND=cuda
export TMPDIR=${SLURM_TMPDIR:-$SCRATCH/tmp}
mkdir -p "$XDG_CACHE_HOME" "$TMPDIR"
