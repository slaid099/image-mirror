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

# 4. ComfyUI v0.42.1
WORKDIR /workspace/ComfyUI
RUN git clone --depth 1 --branch v0.42.1 https://github.com/comfyanonymous/ComfyUI.git . \
    && uv pip install --system --break-system-packages -r requirements.txt

# 5. Модели
WORKDIR /workspace/ComfyUI/models/diffusion_models
RUN mkdir -p ../text_encoders ../vae

# 5.1 Krea 2 fp8 весит 12.24 ГБ — больше лимита GHCR (10 ГБ на слой).
# Поэтому качается двумя Range-запросами, каждый в своём слое.
# Склейка — в start.sh (локальный cat, без сети).
RUN curl -fL -r 0-5999999999 -o krea2_turbo_fp8_scaled.part1 \
    "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/diffusion_models/krea2_turbo_fp8_scaled.safetensors"

RUN curl -fL -r 6000000000- -o krea2_turbo_fp8_scaled.part2 \
    "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/diffusion_models/krea2_turbo_fp8_scaled.safetensors"

RUN curl -fL -o ../text_encoders/qwen3vl_4b_fp8_scaled.safetensors \
    "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/text_encoders/qwen3vl_4b_fp8_scaled.safetensors"

RUN curl -fL -o ../vae/qwen_image_vae.safetensors \
    "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/vae/qwen_image_vae.safetensors"

# 6. Запуск
WORKDIR /workspace/ComfyUI
COPY build/article-gen/start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 22 8188
ENTRYPOINT ["/bin/bash", "/start.sh"]
