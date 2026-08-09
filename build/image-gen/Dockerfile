FROM pytorch/pytorch:2.6.0-cuda12.6-cudnn9-runtime

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV UV_SYSTEM_PYTHON=1

ARG CIVITAI_TOKEN
ENV CIVITAI_TOKEN=${CIVITAI_TOKEN}

# 1. Системные зависимости и SSH
RUN apt-get update && apt-get install -y \
    openssh-server git libgl1 libglib2.0-0 curl wget aria2 \
    && rm -rf /var/lib/apt/lists/*

# 2. Установка uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# 3. Настройка SSH (root:root)
RUN mkdir /var/run/sshd && \
    echo 'root:root' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config

# 4. Установка ComfyUI
WORKDIR /workspace/ComfyUI
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI .
# Ставим зависимости, игнорируя torch/torchvision, так как они уже есть в идеальном виде в базовом образе
RUN uv pip install --system --break-system-packages -r requirements.txt --no-deps torch torchvision torchaudio
RUN uv pip install --system --break-system-packages -r requirements.txt
RUN uv pip install --system --break-system-packages huggingface_hub requests

# 5. Установка ComfyUI-Manager
WORKDIR /workspace/ComfyUI/custom_nodes
RUN git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git

# 6. СКАЧИВАНИЕ МОДЕЛЕЙ (Запекаем всё в образ)
WORKDIR /workspace/ComfyUI/models

# 6.1 Unet (Flux FP8)
RUN mkdir -p unet && \
    aria2c -x 16 -s 16 -d unet -o flux1-dev-fp8.safetensors \
    "https://huggingface.co/Kijai/flux-fp8/resolve/main/flux1-dev-fp8.safetensors"

# 6.2 CLIP Encoders
RUN mkdir -p clip && \
    aria2c -x 16 -s 16 -d clip -o t5xxl_fp8_e4m3fn.safetensors \
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors" && \
    aria2c -x 16 -s 16 -d clip -o clip_l.safetensors \
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors"

# 6.3 VAE
RUN mkdir -p vae && \
    aria2c -x 16 -s 16 -d vae -o ae.safetensors \
    "https://huggingface.co/SicariusSicariiStuff/FLUX.1-dev/resolve/main/ae.safetensors"

# 6.4 LoRAs
RUN mkdir -p loras && \
    # Nokia Style (Civitai, требует токен)
    aria2c -x 16 -s 16 -d loras -o n0k1a.safetensors \
    "https://civitai.com/api/download/models/2046810?type=Model&format=SafeTensor&token=${CIVITAI_TOKEN}" && \
    # Real Skin Texture (Civitai, требует токен)
    aria2c -x 16 -s 16 -d loras -o real_skin.safetensors \
    "https://civitai.com/api/download/models/1026423?token=${CIVITAI_TOKEN}" && \
    # Hyper Flux (Accelerate to 8 steps) — HuggingFace, без токена
    aria2c -x 16 -s 16 -d loras -o hyper_flux_8step.safetensors \
    "https://huggingface.co/ByteDance/Hyper-SD/resolve/main/Hyper-FLUX.1-dev-8steps-lora.safetensors"

# Female Body Milf (Local file, скачивается из Forgejo Packages в build context)
COPY FemaleBody_milf_9.safetensors /workspace/ComfyUI/models/loras/FemaleBody_milf_9.safetensors

# 6.5 Upscale Models
RUN mkdir -p upscale_models && \
    aria2c -x 16 -s 16 -d upscale_models -o 4x-UltraSharp.pth \
    "https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth"

# 7. Настройка скрипта запуска
WORKDIR /workspace/ComfyUI
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 22 8188

# ENTRYPOINT гарантирует выполнение start.sh при каждом запуске
ENTRYPOINT ["/bin/bash", "/start.sh"]