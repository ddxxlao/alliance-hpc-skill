#!/bin/bash
# Runs ON THE CLUSTER LOGIN NODE (hpc setup-env uploads it to ~/venvs and starts it with nohup).
# Builds ~/venvs/sglang from the Alliance wheelhouse only (--no-index). Takes ~30-40 min on the
# network home filesystem; that is normal. Venv lives in HOME, never in /project (file quota).
set -eo pipefail
source ~/venvs/sglang-modules.sh
if [ ! -x ~/venvs/sglang/bin/python ]; then
  virtualenv --no-download ~/venvs/sglang
fi
source ~/venvs/sglang/bin/activate
pip install --no-index --upgrade pip
pip install --no-index torch sglang
python -c "import torch, sglang; print('torch', torch.__version__, 'sglang', sglang.__version__)"
echo INSTALL_DONE
