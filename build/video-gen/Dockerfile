FROM pytorch/pytorch:2.6.0-cuda12.6-cudnn9-runtime

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    UV_SYSTEM_PYTHON=1 \
    COMFYUI_PATH="/workspace/ComfyUI"

ARG CIVITAI_TOKEN

# 1. Системные зависимости
RUN apt-get update && apt-get install -y \
    git curl wget ffmpeg libgl1 libglib2.0-0 \
    build-essential python3-dev openssh-server \
    && ln -s /usr/lib/x86_64-linux-gnu/libcuda.so.1 /usr/lib/x86_64-linux-gnu/libcuda.so \
    && export LD_LIBRARY_PATH=/usr/local/cuda/lib64/stubs:$LD_LIBRARY_PATH \
    && rm -rf /var/lib/apt/lists/*

# 2. Установка UV
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# 3. Клонируем ComfyUI
WORKDIR /workspace
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git

# 4. Установка кастомных нод (WanVideo, VHS, Interpolation, FaceRestore, KJNodes, Manager)
WORKDIR /workspace/ComfyUI/custom_nodes
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone https://github.com/Kijai/ComfyUI-WanVideoWrapper.git && \
    git clone https://github.com/Kijai/ComfyUI-VideoHelperSuite.git && \
    git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git && \
    git clone https://github.com/mav-rik/facerestore_cf.git && \
    git clone https://github.com/kijai/ComfyUI-KJNodes.git

# 5. Установка зависимостей
# Пинним comfy-kitchen==0.1.0 (0.2.x ломается на torch 2.6.0: list[int] в infer_schema)
# Удаляем torch/torchvision/torchaudio из requirements — оставляем 2.6.0 из базового образа
WORKDIR /workspace/ComfyUI
RUN sed -i 's/^comfy-kitchen.*/comfy-kitchen==0.1.0/' requirements.txt && \
    sed -i '/^torch$/d;/^torchvision$/d;/^torchaudio$/d' requirements.txt && \
    uv pip install --system --break-system-packages -r requirements.txt
RUN find custom_nodes -maxdepth 2 -name "requirements.txt" -exec sh -c 'cat {}; echo ""' \; > all_reqs.txt && \
    uv pip install --system --break-system-packages -r all_reqs.txt
RUN uv pip install --system --break-system-packages \
    huggingface_hub requests imageio-ffmpeg sageattention scikit-image opencv-python

# 6. СКАЧИВАНИЕ МОДЕЛЕЙ (всё из облака через curl -L)
WORKDIR /workspace/ComfyUI/models

# 6.1 Основная модель Wan (All-in-one) — Civitai
RUN mkdir -p checkpoints && \
    curl -L -o checkpoints/wanLOVELowVRAMImageTo_i2v14BFp8.safetensors \
    "https://civitai.com/api/download/models/2129615?token=${CIVITAI_TOKEN}"

# 6.2 LoRAs — Civitai
RUN mkdir -p loras && \
    curl -L -o loras/intimate_handheld_grainy_video.safetensors \
    "https://civitai.com/api/download/models/1865295?token=${CIVITAI_TOKEN}" && \
    curl -L -o loras/motion_craft.safetensors \
    "https://civitai.com/api/download/models/1599906?token=${CIVITAI_TOKEN}" && \
    curl -L -o loras/round_body_rotation.safetensors \
    "https://civitai.com/api/download/models/1683094?token=${CIVITAI_TOKEN}"

# 6.3 Вспомогательные модели — HuggingFace + GitHub
RUN mkdir -p upscale_models && \
    curl -L -o upscale_models/4x-UltraSharp.pth \
    "https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth"
RUN mkdir -p facerestore_models && \
    curl -L -o facerestore_models/codeformer.pth \
    "https://github.com/sczhou/CodeFormer/releases/download/v0.1.0/codeformer.pth"
RUN mkdir -p /workspace/ComfyUI/custom_nodes/ComfyUI-Frame-Interpolation/ckpts/rife/ && \
    curl -L -o /workspace/ComfyUI/custom_nodes/ComfyUI-Frame-Interpolation/ckpts/rife/rife47.pth \
    "https://huggingface.co/jasonot/mycomfyui/resolve/main/rife47.pth"
RUN mkdir -p clip_vision && \
    curl -L -o clip_vision/clip_vision_h.safetensors \
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors"

# 7. Настройка SSH для Vast.ai
RUN mkdir /var/run/sshd && \
    echo 'root:root' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# 8. Скрипт запуска
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 22 8188
ENTRYPOINT ["/bin/bash", "/start.sh"]