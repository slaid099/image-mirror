FROM pytorch/pytorch:2.9.1-cuda12.8-cudnn9-runtime

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    UV_SYSTEM_PYTHON=1

# 1. Системные зависимости и SSH
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server git curl libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# 2. uv (конвенция репозитория)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# 3. SSH root:root
RUN mkdir -p /var/run/sshd && \
    echo 'root:root' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config

# 4. ComfyUI v0.42.1 (FLUX.3 требует >= 0.41.0).
# Без старых пинов comfy-kitchen==0.2.7 — они были нужны только для torch 2.6.
WORKDIR /workspace/ComfyUI
RUN git clone --depth 1 --branch v0.42.1 https://github.com/comfyanonymous/ComfyUI.git . \
    && uv pip install --system --break-system-packages -r requirements.txt

# 5. Модели (каждый файл — отдельный слой, < 10 ГБ)
WORKDIR /workspace/ComfyUI/models
RUN mkdir -p diffusion_models text_encoders vae

RUN curl -fL -o diffusion_models/flux3-image-klein-int8-convrot.safetensors \
    "https://huggingface.co/ml-resources/flux-3-image-klein-comfy/resolve/main/diffusion_models/flux3-image-klein-int8-convrot.safetensors"

RUN curl -fL -o text_encoders/qwen3vl_4b_int8_convrot.safetensors \
    "https://huggingface.co/ml-resources/flux-3-image-klein-comfy/resolve/main/text_encoders/qwen3vl_4b_int8_convrot.safetensors"

RUN curl -fL -o vae/flux2-vae.safetensors \
    "https://huggingface.co/ml-resources/flux-3-image-klein-comfy/resolve/main/vae/flux2-vae.safetensors"

# 6. Запуск
WORKDIR /workspace/ComfyUI
COPY build/article-gen/start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 22 8188
ENTRYPOINT ["/bin/bash", "/start.sh"]
