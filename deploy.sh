#!/bin/bash
# deploy.sh — Deploy QWEST GGUF model to RunPod (RTX A5000)
#
# Usage:
#   export RUNPOD_API_KEY=rpa_...
#   ./deploy.sh

set -e

echo "=============================================="
echo "QWEST LLM — RunPod Deployment"
echo "=============================================="

# Validate RUNPOD_API_KEY
if [ -z "$RUNPOD_API_KEY" ]; then
    echo "ERROR: RUNPOD_API_KEY not set"
    echo "Usage: export RUNPOD_API_KEY=rpa_... && ./deploy.sh"
    exit 1
fi

# R2 credentials (from environment or use defaults)
R2_ACCOUNT_ID="${R2_ACCOUNT_ID:-ff3f1e19718d7d5205d5a86177e2c9cd}"
R2_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID:-689224e50206f382b22cf8d1ef391a56}"
R2_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY:-ae1a97da0d55d34ec0294e97daefef218e6898142afb20b9952de061b043c020}"
R2_BUCKET_NAME="${R2_BUCKET_NAME:-ayeboard}"

# Model config
MODEL_REMOTE_PATH="${MODEL_REMOTE_PATH:-qwest-llm/qwest-v11-q4_k_m.gguf}"
IMAGE_NAME="ghcr.io/bharath-ayelabz/runpod-qwest-server:latest"
PORT="${PORT:-8080}"
CTX_SIZE="${CTX_SIZE:-2048}"
N_GPU_LAYERS="${N_GPU_LAYERS:-99}"

echo "Container: $IMAGE_NAME"
echo "Model: r2://${R2_BUCKET_NAME}/${MODEL_REMOTE_PATH}"
echo ""

# ---- Create pod via RunPod REST API ----
POD_NAME="qwest-llm-v11-$(date +%Y%m%d)"

echo "[Step 1] Creating pod..."
RESP=$(curl -s -X POST "https://rest.runpod.io/v1/pods" \
    -H "Authorization: Bearer $RUNPOD_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"$POD_NAME\",
        \"imageName\": \"$IMAGE_NAME\",
        \"gpuTypeIds\": [\"NVIDIA RTX A5000\"],
        \"volumeInGb\": 30,
        \"env\": {
            \"R2_ACCOUNT_ID\": \"$R2_ACCOUNT_ID\",
            \"R2_ACCESS_KEY_ID\": \"$R2_ACCESS_KEY_ID\",
            \"R2_SECRET_ACCESS_KEY\": \"$R2_SECRET_ACCESS_KEY\",
            \"R2_BUCKET_NAME\": \"$R2_BUCKET_NAME\",
            \"MODEL_REMOTE_PATH\": \"$MODEL_REMOTE_PATH\",
            \"PORT\": \"$PORT\",
            \"CTX_SIZE\": \"$CTX_SIZE\",
            \"N_GPU_LAYERS\": \"$N_GPU_LAYERS\"
        },
        \"ports\": [\"$PORT/http\"]
    }")

echo "Response: $RESP"

POD_ID=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id','') or '')" 2>/dev/null || echo "")

if [ -z "$POD_ID" ]; then
    echo ""
    echo "ERROR: Failed to create pod."
    echo "Response: $RESP"
    exit 1
fi

echo "  Pod ID: $POD_ID"

# ---- Wait for RUNNING ----
echo ""
echo "[Step 2] Waiting for pod to become RUNNING (5-15 min for cold start)..."

for i in $(seq 1 90); do
    sleep 10
    STATUS=$(curl -s "https://rest.runpod.io/v1/pods/$POD_ID" \
        -H "Authorization: Bearer $RUNPOD_API_KEY" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('runtime',{}).get('desiredStatus') or d.get('desiredStatus') or 'UNKNOWN')" 2>/dev/null || echo "UNKNOWN")
    echo "  [$i] Status: $STATUS"
    if [ "$STATUS" = "RUNNING" ]; then
        break
    fi
done

if [ "$STATUS" != "RUNNING" ]; then
    echo "Pod did not reach RUNNING state after 15 min. Check console."
    exit 1
fi

# ---- Get endpoint ----
POD_INFO=$(curl -s "https://rest.runpod.io/v1/pods/$POD_ID" \
    -H "Authorization: Bearer $RUNPOD_API_KEY")

ENDPOINT=$(echo "$POD_INFO" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('runtime',{}).get('endpoint','') or '')" 2>/dev/null || echo "")
API_URL="https://${ENDPOINT}"
[ -z "$ENDPOINT" ] && API_URL="https://${POD_ID}.proxy.runpod.net"

# ---- Save info ----
cat > "$(dirname "$0")/.deployment_info" << EOF
POD_ID=$POD_ID
ENDPOINT=$API_URL
MODEL=r2://${R2_BUCKET_NAME}/${MODEL_REMOTE_PATH}
PORT=$PORT
IMAGE=$IMAGE_NAME
DEPLOYED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GPU_TYPE=NVIDIA RTX A5000
EOF

echo ""
echo "=============================================="
echo "✅ Deployment Complete!"
echo "=============================================="
echo "  Pod ID:    $POD_ID"
echo "  API URL:   $API_URL"
echo ""
echo "  Model:     r2://$R2_BUCKET_NAME/$MODEL_REMOTE_PATH"
echo ""
echo "  Test: curl -X POST $API_URL/v1/chat/completions \\"
echo '       -H "Content-Type: application/json" \'
echo '       -d {"messages":[{"role":"system","content":"You are QWEST..."},{"role":"user","content":"..."}]}'