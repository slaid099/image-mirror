#!/bin/bash

# 1. SSH (нужен для отладки на Vast.ai)
/usr/sbin/sshd
echo "--- SSH Started ---"

# 2. Проброс переменных окружения из PID 1 (Vast.ai)
echo "--- Uploading variables from /proc/1/environ ---"
for line in $(cat /proc/1/environ | tr '\0' '\n' | grep -v "LS_COLORS"); do
    export "$line" || true
done

cd /workspace/ComfyUI

# 3. Склейка разрезанных чекпоинтов (лимит GHCR: 10 ГБ на слой).
# Krea 2 fp8 весит 12.24 ГБ и лежит двумя частями. Это локальный cat,
# сеть не используется — образ остаётся полностью запечённым.
if [ -f models/diffusion_models/krea2_turbo_fp8_scaled.part1 ]; then
    echo "--- Joining krea2_turbo_fp8_scaled parts ---"
    cat models/diffusion_models/krea2_turbo_fp8_scaled.part1 \
        models/diffusion_models/krea2_turbo_fp8_scaled.part2 \
        > models/diffusion_models/krea2_turbo_fp8_scaled.safetensors
    rm -f models/diffusion_models/krea2_turbo_fp8_scaled.part1 \
          models/diffusion_models/krea2_turbo_fp8_scaled.part2
fi

echo "--- Starting ComfyUI ---"
python3 -u main.py --listen 0.0.0.0 --port 8188 2>&1 | tee -a /workspace/setup.log
