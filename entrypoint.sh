#!/bin/bash
# NEVER use set -e: handler must start for worker to register as ready

echo "=========================================="
echo "LTX-2 19B Text-to-Video - Container startup - $(date)"
echo "=========================================="

# Network Volume Setup
NETVOLUME="${NETWORK_VOLUME_PATH:-/runpod-volume}"

echo "Checking Network Volume at $NETVOLUME..."
if [ ! -d "$NETVOLUME" ]; then
    echo "WARNING: Network Volume not found at $NETVOLUME"
    echo "Handler will start but jobs will fail without models"
fi

# Create symlinks (only if volume exists)
if [ -d "$NETVOLUME/models" ]; then
    echo "Creating symlinks..."
    rm -rf /ComfyUI/models/checkpoints
    rm -rf /ComfyUI/models/text_encoders
    rm -rf /ComfyUI/models/clip
    rm -rf /ComfyUI/models/loras
    rm -rf /ComfyUI/models/latent_upscale_models
    rm -rf /ComfyUI/models/vae

    ln -sf $NETVOLUME/models/checkpoints /ComfyUI/models/checkpoints
    ln -sf $NETVOLUME/models/text_encoders /ComfyUI/models/text_encoders
    ln -sf $NETVOLUME/models/text_encoders /ComfyUI/models/clip
    ln -sf $NETVOLUME/models/loras /ComfyUI/models/loras
    ln -sf $NETVOLUME/models/latent_upscale_models /ComfyUI/models/latent_upscale_models
    ln -sf $NETVOLUME/models/vae /ComfyUI/models/vae
    echo "Symlinks created!"
else
    echo "WARNING: $NETVOLUME/models not found, skipping symlinks"
fi

# Model verification (warnings only, never exit)
check_model() {
    local model_path="$1"
    local model_name="$2"

    if [ ! -f "$model_path" ]; then
        echo "  [MISSING] $model_name ($model_path)"
    else
        echo "  [OK] $model_name"
    fi
}

echo "Verifying models..."
check_model "$NETVOLUME/models/checkpoints/ltx-2-19b-dev-fp8.safetensors" "LTX-2 19B FP8 Checkpoint"
check_model "$NETVOLUME/models/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors" "Gemma 3 12B Text Encoder"
check_model "$NETVOLUME/models/loras/ltx-2-19b-distilled-lora-384.safetensors" "LTX-2 Distilled LoRA"
check_model "$NETVOLUME/models/latent_upscale_models/ltx-2-spatial-upscaler-x2-1.0.safetensors" "LTX-2 Spatial Upscaler"

# GPU Detection
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "Unknown")
echo "Detected GPU: $GPU_NAME"

# Start ComfyUI
echo "Starting ComfyUI..."
python /ComfyUI/main.py --listen &

# Wait for ComfyUI
echo "Waiting for ComfyUI..."
max_wait=180
wait_count=0
while [ $wait_count -lt $max_wait ]; do
    if curl -s http://127.0.0.1:8188/ > /dev/null 2>&1; then
        echo "ComfyUI is ready!"
        break
    fi
    sleep 2
    wait_count=$((wait_count + 2))
done

if [ $wait_count -ge $max_wait ]; then
    echo "WARNING: ComfyUI failed to start within timeout, starting handler anyway"
fi

# CRITICAL: Handler MUST start for worker to register as ready
echo "Starting handler..."
exec python handler.py
