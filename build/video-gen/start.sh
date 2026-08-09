#!/bin/bash

# 1. Запускаем SSH
if [ -x "/usr/sbin/sshd" ]; then
    /usr/sbin/sshd
    echo "--- SSH Started ---"
fi

# 2. Проброс переменных (с защитой от ошибок || true)
# Это критично для Vast.ai, чтобы переменные окружения были доступны в Python
for line in $(cat /proc/1/environ | tr '\0' '\n' | grep -v "LS_COLORS"); do
    export "$line" || true
done

echo "--- Variables uploaded. Starting Python ---"

cd /workspace/ComfyUI

# 3. Доустановка зависимостей при старте (Safety net)
# imageio-ffmpeg нужен для записи видео, huggingface_hub для скачивания
uv pip install --system --break-system-packages huggingface_hub requests imageio-ffmpeg gitpython sageattention scikit-image opencv-python onnxruntime toml ftfy gguf sqlalchemy comfy-aimdo regex -r requirements.txt

# Установка зависимостей для всех кастомных нод
find custom_nodes -maxdepth 2 -name "requirements.txt" -exec uv pip install --system --break-system-packages -r {} \;

echo "--- Dependencies installed. Starting ComfyUI Direct ---"

# 4. Настройка окружения HuggingFace
export HF_HOME="/workspace/huggingface"

# 5. Запуск ComfyUI напрямую
python3 -u main.py --listen 0.0.0.0 --port 8188 2>&1 | tee -a /workspace/setup.log