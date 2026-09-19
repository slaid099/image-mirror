FROM pytorch/pytorch:2.6.0-cuda12.6-cudnn9-runtime

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    UV_SYSTEM_PYTHON=1 \
    COMFYUI_PATH="/workspace/ComfyUI" \
    HF_HOME="/workspace/huggingface"

# 1. Системные зависимости
RUN apt-get update && apt-get install -y \
    git curl wget ffmpeg libgl1 libglib2.0-0 \
    build-essential python3-dev openssh-server \
    && ln -s /usr/lib/x86_64-linux-gnu/libcuda.so.1 /usr/lib/x86_64-linux-gnu/libcuda.so \
    && export LD_LIBRARY_PATH=/usr/local/cuda/lib64/stubs:$LD_LIBRARY_PATH \
    && rm -rf /var/lib/apt/lists/*

# 2. Установка UV
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# 3. Клонируем ComfyUI (пин рабочего коммита с нативной поддержкой LTX-2.5)
WORKDIR /workspace
RUN git clone https://github.com/comfyanonymous/ComfyUI.git && \
    cd ComfyUI && \
    git checkout 3c80da7f87ee359b2d06f107cb3c0797079dfbbb

# 4. Кастомные ноды: Manager + VideoHelperSuite (VideoCombine — сохранение в .mp4)
WORKDIR /workspace/ComfyUI/custom_nodes
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone https://github.com/Kijai/ComfyUI-VideoHelperSuite.git

# 5. Готовим requirements: убираем torch (заменяем на 2.14) и comfy-kitchen
#    (свежий ComfyUI жёстко требует comfy-kitchen 0.2.35, пин 0.2.7 ломает импорт)
WORKDIR /workspace/ComfyUI
RUN sed -i '/^torch$/d;/^torchvision$/d;/^torchaudio$/d;/^comfy-kitchen/d' requirements.txt

# 6. МОДЕЛИ — копируем РАНЬШЕ pip-шагов, чтобы правки зависимостей
#    не инвалидировали 48 GB слоёв при пересборке
WORKDIR /workspace/ComfyUI/models
COPY models/diffusion_models/ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors \
    diffusion_models/ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors
COPY models/text_encoders/gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors \
    text_encoders/gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors
COPY models/text_encoders/gemma4_e2b_it_bf16.safetensors \
    text_encoders/gemma4_e2b_it_bf16.safetensors
COPY models/vae/ltx-2.5-video-vae-bf16.safetensors \
    vae/ltx-2.5-video-vae-bf16.safetensors
COPY models/vae/ltx-2.5-audio-vae-bf16.safetensors \
    vae/ltx-2.5-audio-vae-bf16.safetensors
COPY models/latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors \
    latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors

# 7. Установка зависимостей (связка, проверенная на vast.ai L40S с драйвером CUDA 12.6):
#    torch 2.13.0+cu129 + comfy-kitchen 0.2.35 — обязательная пара для LTX-2.5 int8.
#    ВАЖНО: только cu12x-сборки — cu130 требует драйвер CUDA 13 и падает на хостах vast с 12.6.
#    ВАЖНО: версии с ЯВНЫМ локальным тегом (+cu129) — без него pip выбирает +cu130
#    по лексикографическому правилу и тянет wheel из PyPI (несовместимый libcudart.so.13)
WORKDIR /workspace/ComfyUI
RUN uv pip install --system --break-system-packages -r requirements.txt
RUN uv pip install --system --break-system-packages \
    torch==2.13.0+cu129 torchvision==0.28.0+cu129 \
    --index-url https://download.pytorch.org/whl/cu129 && \
    uv pip install --system --break-system-packages --no-deps \
    torchaudio==2.11.0+cu129 --index-url https://download.pytorch.org/whl/cu129 && \
    uv pip install --system --break-system-packages comfy-kitchen==0.2.35
RUN find custom_nodes -maxdepth 2 -name "requirements.txt" -exec sh -c 'cat {}; echo ""' \; > all_reqs.txt && \
    sed -i '/^comfy-kitchen/d;/^torch$/d;/^torchvision$/d;/^torchaudio$/d' all_reqs.txt && \
    uv pip install --system --break-system-packages -r all_reqs.txt
RUN uv pip install --system --break-system-packages \
    huggingface_hub requests imageio-ffmpeg sageattention scikit-image opencv-python

# 8. Настройка SSH для Vast.ai
RUN mkdir /var/run/sshd && \
    echo 'root:root' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# 9. Скрипт запуска
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 22 8188
ENTRYPOINT ["/bin/bash", "/start.sh"]