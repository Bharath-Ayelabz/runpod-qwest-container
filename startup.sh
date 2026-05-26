#!/bin/bash
# startup.sh — QWEST GGUF Model Server
# Downloads model from R2 and starts Python server with llama-cpp-python

set -e

echo "=============================================="
echo "QWEST LLM — Starting up"
echo "=============================================="

# Check env vars
if [ -z "$R2_ACCOUNT_ID" ] || [ -z "$R2_ACCESS_KEY_ID" ] || [ -z "$R2_SECRET_ACCESS_KEY" ] || [ -z "$R2_BUCKET_NAME" ]; then
    echo "ERROR: R2 credentials not set"
    exit 1
fi

MODEL_REMOTE_PATH="${MODEL_REMOTE_PATH:-qwest-llm/qwest-v11-q4_k_m.gguf}"
MODEL_LOCAL_PATH="/app/model.gguf"
PORT="${PORT:-8080}"
CTX_SIZE="${CTX_SIZE:-2048}"
N_GPU_LAYERS="${N_GPU_LAYERS:-99}"

echo "Model: r2://${R2_BUCKET_NAME}/${MODEL_REMOTE_PATH}"
echo "Port: $PORT"
echo "Context size: $CTX_SIZE"
echo "GPU layers: $N_GPU_LAYERS"

# Install wget and configure R2
apt-get update && apt-get install -y wget > /dev/null 2>&1 || true

export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export AWS_ENDPOINT_URL="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"

# Download model from R2 using wget
if [ ! -f "$MODEL_LOCAL_PATH" ]; then
    echo ""
    echo "[1/2] Downloading model from R2 (~1.8GB, may take a few minutes)..."
    wget --no-check-certificate -q -O "$MODEL_LOCAL_PATH" \
        "${AWS_ENDPOINT_URL}/${R2_BUCKET_NAME}/${MODEL_REMOTE_PATH}"
    echo "✅ Model downloaded: $(du -h $MODEL_LOCAL_PATH | cut -f1)"
else
    echo "✅ Model already exists: $(du -h $MODEL_LOCAL_PATH | cut -f1)"
fi

# Start the Python server
echo ""
echo "[2/2] Starting QWEST API server on port $PORT..."
echo "=============================================="

cd /app
exec /opt/venv/bin/python3 server.py \
    --model "$MODEL_LOCAL_PATH" \
    --port "$PORT" \
    --ctx-size "$CTX_SIZE" \
    --gpu-layers "$N_GPU_LAYERS" \
    2>&1