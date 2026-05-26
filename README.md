# QWEST RunPod Deployment

## What's Deployed

- **Model:** `qwest-v11-q4_k_m.gguf` (Qwen2.5:3B fine-tuned on K-12 curriculum)
- **Quantization:** Q4_K_M (1.8GB)
- **GPU:** RTX A5000 (24GB VRAM)
- **Serving:** llama-cpp-python with CUDA GPU offloading
- **API:** OpenAI-compatible `/v1/chat/completions`

## Files

```
runpod-qwest-deploy/
├── Dockerfile          # Container image definition
├── server.py           # Python API server (Flask + llama-cpp-python)
├── startup.sh          # Container startup script
├── deploy.sh           # Deploy to RunPod
└── README.md           # This file
```

## Quick Deploy

```bash
cd ~/.openclaw/workspace/runpod-qwest-deploy

# Set API key
export RUNPOD_API_KEY=your_runpod_api_key

# Deploy
chmod +x deploy.sh
./deploy.sh
```

## After Deployment

The API will be available at:
```
POST https://<endpoint>/v1/chat/completions
```

Example request:
```python
import requests

response = requests.post(
    "https://YOUR_ENDPOINT/v1/chat/completions",
    headers={"Content-Type": "application/json"},
    json={
        "messages": [
            {"role": "system", "content": "You are QWEST, an expert Indian K-12 educational AI."},
            {"role": "user", "content": '{"topic": "Force & Pressure", "grade": 8, "board": "CBSE", "difficulty": "medium", "num_questions": 3}'}
        ],
        "max_tokens": 800,
        "temperature": 0.1
    }
)
print(response.json())
```

## Manual Build (if needed)

```bash
docker build --platform linux/amd64 -t ghcr.io/your-username/runpod-qwest-server:latest .
docker push ghcr.io/your-username/runpod-qwest-server:latest
```