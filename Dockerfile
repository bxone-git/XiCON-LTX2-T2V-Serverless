# LTX-2 19B Text-to-Video - Network Volume
# CUDA 12.8 + PyTorch cu128 (devel for 5090 Blackwell sm_120) + SageAttention
# Tag: ghcr.io/bxone-git/xicon-ltx2-t2v-serverless:latest

FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 python3-pip python3.10-venv \
    git curl wget \
    libgl1-mesa-glx libglib2.0-0 \
    ffmpeg libsndfile1 \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/python3.10 /usr/bin/python

# PyTorch with CUDA 12.8 (includes torchaudio for audio/video processing)
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128

# SageAttention for 3x speedup on 5090
RUN pip install --no-cache-dir triton sageattention --no-build-isolation

# Python packages
RUN pip install --no-cache-dir -U "huggingface_hub[hf_transfer]" runpod websocket-client

WORKDIR /

# ComfyUI
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git && \
    cd /ComfyUI && pip install --no-cache-dir -r requirements.txt

# Custom nodes (ComfyUI-Manager only for LTX-2)
RUN cd /ComfyUI/custom_nodes && \
    git clone --depth 1 https://github.com/Comfy-Org/ComfyUI-Manager.git && \
    cd ComfyUI-Manager && pip install --no-cache-dir -r requirements.txt

# Model directories (symlinked at runtime from network volume)
RUN mkdir -p /ComfyUI/models/checkpoints \
    /ComfyUI/models/text_encoders \
    /ComfyUI/models/loras \
    /ComfyUI/models/latent_upscale_models \
    /ComfyUI/models/vae \
    /ComfyUI/models/clip \
    /ComfyUI/input \
    /ComfyUI/output

# Cleanup to save space
RUN rm -rf /root/.cache /tmp/* /var/tmp/*

# NO MODEL DOWNLOADS - Network Volume 사용

# Create directory structure first (before copying files)
RUN mkdir -p /ComfyUI/user/default/ComfyUI-Manager

# Copy stable config first (changes rarely)
COPY config.ini /ComfyUI/user/default/ComfyUI-Manager/config.ini

# Copy volatile application code LAST (changes frequently)
COPY handler.py /handler.py
COPY entrypoint.sh /entrypoint.sh
COPY workflow_api.json /workflow_api.json
COPY setup_netvolume.sh /setup_netvolume.sh

# Set permissions
RUN chmod +x /entrypoint.sh /setup_netvolume.sh

CMD ["/entrypoint.sh"]
