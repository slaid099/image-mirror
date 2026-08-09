FROM pytorch/pytorch:2.6.0-cuda12.6-cudnn9-runtime

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV UV_SYSTEM_PYTHON=1

ARG CIVITAI_TOKEN

# 1. Системные зависимости и SSH
RUN apt-get update && apt-get install -y \
    openssh-server git libgl1 libglib2.0-0 curl wget \
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
# Пинним comfy-kitchen==0.2.7 (доказанно рабочая версия из video-gen:v2 на Python 3.11 + torch 2.6.0)
# 0.1.0 требует Python>=3.12, 0.2.7+ требуют >=3.10. Версии 0.2.27/0.2.28 ломаются на torch 2.6 (list[int] в na.py)
# Заменяем ЛЮБУЮ версию comfy-kitchen на ==0.2.7
# Удаляем torch/torchvision/torchaudio из requirements — оставляем 2.6.0 из базового образа
RUN sed -i -E 's/^comfy-kitchen.*/comfy-kitchen==0.2.7/' requirements.txt && \
    sed -i '/^torch$/d;/^torchvision$/d;/^torchaudio$/d' requirements.txt && \
    uv pip install --system --break-system-packages -r requirements.txt
RUN uv pip install --system --break-system-packages huggingface_hub requests

# 5. Установка ComfyUI-Manager
WORKDIR /workspace/ComfyUI/custom_nodes
RUN git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git

# 6. СКАЧИВАНИЕ МОДЕЛЕЙ (Запекаем всё в образ)
WORKDIR /workspace/ComfyUI/models

# 6.1 Unet (Flux FP8) — HuggingFace
RUN mkdir -p unet && \
    curl -L -o unet/flux1-dev-fp8.safetensors \
    "https://huggingface.co/Kijai/flux-fp8/resolve/main/flux1-dev-fp8.safetensors"

# 6.2 CLIP Encoders — HuggingFace
RUN mkdir -p clip && \
    curl -L -o clip/t5xxl_fp8_e4m3fn.safetensors \
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors" && \
    curl -L -o clip/clip_l.safetensors \
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors"

# 6.3 VAE — HuggingFace
RUN mkdir -p vae && \
    curl -L -o vae/ae.safetensors \
    "https://huggingface.co/SicariusSicariiStuff/FLUX.1-dev/resolve/main/ae.safetensors"

# 6.4 LoRAs — Civitai (curl -L, токен в query) + HuggingFace
RUN mkdir -p loras && \
    curl -L -o loras/n0k1a.safetensors \
    "https://civitai.com/api/download/models/2046810?type=Model&format=SafeTensor&token=${CIVITAI_TOKEN}" && \
    curl -L -o loras/real_skin.safetensors \
    "https://civitai.com/api/download/models/1026423?token=${CIVITAI_TOKEN}" && \
    curl -L -o loras/hyper_flux_8step.safetensors \
    "https://huggingface.co/ByteDance/Hyper-SD/resolve/main/Hyper-FLUX.1-dev-8steps-lora.safetensors"

# Female Body Milf (Local file из Forgejo Packages)
COPY FemaleBody_milf_9.safetensors /workspace/ComfyUI/models/loras/FemaleBody_milf_9.safetensors

# 6.5 Upscale Models — HuggingFace
RUN mkdir -p upscale_models && \
    curl -L -o upscale_models/4x-UltraSharp.pth \
    "https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth"

# 7. Настройка скрипта запуска
WORKDIR /workspace/ComfyUI
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 22 8188

ENTRYPOINT ["/bin/bash", "/start.sh"]