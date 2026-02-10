#!/bin/bash
set -e

NETVOLUME="/runpod-volume"

echo "=========================================="
echo "LTX-2 19B Text-to-Video - Network Volume Setup"
echo "Network Volume: XiCON"
echo "=========================================="

if [ ! -d "$NETVOLUME" ]; then
    echo "ERROR: Network Volume not found at $NETVOLUME"
    echo "Please attach network volume 'XiCON' with mount path /runpod-volume"
    exit 1
fi

# Create directory structure
echo "Creating directory structure..."
mkdir -p $NETVOLUME/models/checkpoints
mkdir -p $NETVOLUME/models/text_encoders
mkdir -p $NETVOLUME/models/loras
mkdir -p $NETVOLUME/models/latent_upscale_models

# [1/4] LTX-2 model (public URL)
echo ""
echo "[1/4] LTX-2 19B model (~19GB)"
if [ ! -f "$NETVOLUME/models/checkpoints/ltx-2-19b-dev-fp8.safetensors" ]; then
    echo "Downloading LTX-2 model..."
    wget -q --show-progress \
        "https://huggingface.co/Lightricks/LTX-2/resolve/main/ltx-2-19b-dev-fp8.safetensors" \
        -O "$NETVOLUME/models/checkpoints/ltx-2-19b-dev-fp8.safetensors"
    echo "LTX-2 model downloaded!"
else
    echo "[SKIP] LTX-2 model already exists"
fi

# [2/4] Text Encoder (public URL)
echo ""
echo "[2/4] Text Encoder model (~6GB)"
if [ ! -f "$NETVOLUME/models/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors" ]; then
    echo "Downloading Text Encoder model..."
    wget -q --show-progress \
        "https://huggingface.co/Comfy-Org/ltx-2/resolve/main/split_files/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors" \
        -O "$NETVOLUME/models/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors"
    echo "Text Encoder model downloaded!"
else
    echo "[SKIP] Text Encoder model already exists"
fi

# [3/4] LoRA (public URL)
echo ""
echo "[3/4] LoRA model"
if [ ! -f "$NETVOLUME/models/loras/ltx-2-19b-distilled-lora-384.safetensors" ]; then
    echo "Downloading LoRA model..."
    wget -q --show-progress \
        "https://huggingface.co/Lightricks/LTX-2/resolve/main/ltx-2-19b-distilled-lora-384.safetensors" \
        -O "$NETVOLUME/models/loras/ltx-2-19b-distilled-lora-384.safetensors"
    echo "LoRA model downloaded!"
else
    echo "[SKIP] LoRA model already exists"
fi

# [4/4] Spatial Upscaler (public URL)
echo ""
echo "[4/4] Spatial Upscaler model"
if [ ! -f "$NETVOLUME/models/latent_upscale_models/ltx-2-spatial-upscaler-x2-1.0.safetensors" ]; then
    echo "Downloading Spatial Upscaler model..."
    wget -q --show-progress \
        "https://huggingface.co/Lightricks/LTX-2/resolve/main/ltx-2-spatial-upscaler-x2-1.0.safetensors" \
        -O "$NETVOLUME/models/latent_upscale_models/ltx-2-spatial-upscaler-x2-1.0.safetensors"
    echo "Spatial Upscaler model downloaded!"
else
    echo "[SKIP] Spatial Upscaler model already exists"
fi

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Model sizes:"
du -sh $NETVOLUME/models/checkpoints 2>/dev/null || echo "  checkpoints: (pending)"
du -sh $NETVOLUME/models/text_encoders 2>/dev/null || echo "  text_encoders: (pending)"
du -sh $NETVOLUME/models/loras 2>/dev/null || echo "  loras: (pending)"
du -sh $NETVOLUME/models/latent_upscale_models 2>/dev/null || echo "  latent_upscale_models: (pending)"
echo ""
echo "Total:"
du -sh $NETVOLUME/models
