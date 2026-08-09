#!/bin/bash

# 1. Запуск SSH (нужен для связи с Vast.ai)
/usr/sbin/sshd
echo "--- SSH Started ---"

# 2. Критично для Vast.ai: Проброс переменных окружения из процесса PID 1
echo "--- Uploading variables from /proc/1/environ ---"
for line in $(cat /proc/1/environ | tr '\0' '\n' | grep -v "LS_COLORS"); do
    export "$line" || true
done

echo "--- Variables uploaded. Starting ComfyUI ---"

# 3. Переходим в директорию и запускаем сервер прямо (модели уже запечены)
cd /workspace/ComfyUI
python3 -u main.py --listen 0.0.0.0 --port 8188 --disable-smart-memory 2>&1 | tee -a /workspace/setup.log