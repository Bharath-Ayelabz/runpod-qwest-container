#!/usr/bin/env python3
"""
server.py — QWEST GGUF Model Server
Serves the model via OpenAI-compatible /v1/chat/completions API
using llama-cpp-python with CUDA GPU offloading.
"""

import argparse
import sys
import os
import gc

# Set CUDA devices before importing llama_cpp
cuda_visible_devices = os.environ.get("CUDA_VISIBLE_DEVICES", "0")
os.environ["CUDA_VISIBLE_DEVICES"] = cuda_visible_devices

from flask import Flask, request, jsonify, Response
from llama_cpp import Llama
import llama_cpp

app = Flask(__name__)

# Global model instance
llm = None

def load_model(model_path: str, ctx_size: int, gpu_layers: int):
    """Load GGUF model with GPU offloading."""
    global llm
    print(f"Loading model: {model_path}")
    print(f"  Context size: {ctx_size}")
    print(f"  GPU layers: {gpu_layers}")
    
    llm = Llama(
        model_path=model_path,
        n_ctx=ctx_size,
        n_gpu_layers=gpu_layers,
        verbose=False,
        use_mlock=True,
        use_mmap=True,
    )
    print("Model loaded successfully!")


@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint."""
    if llm is None:
        return jsonify({"status": "loading"}), 503
    return jsonify({"status": "ok", "model": "qwest-v11-q4_k_m"}), 200


@app.route("/v1/models", methods=["GET"])
def list_models():
    """List available models (OpenAI compatible)."""
    return jsonify({
        "data": [{
            "id": "qwest-v11-q4_k_m",
            "object": "model",
            "created": 1716000000,
            "owned_by": "ayeboard",
            "meta": {
                "n_ctx": 2048,
                "quantization": "Q4_K_M"
            }
        }]
    })


@app.route("/v1/chat/completions", methods=["POST"])
def chat_completions():
    """OpenAI-compatible chat completions endpoint."""
    if llm is None:
        return jsonify({"error": "Model not loaded"}), 503
    
    data = request.get_json()
    if not data:
        return jsonify({"error": "Invalid JSON"}), 400
    
    messages = data.get("messages", [])
    max_tokens = data.get("max_tokens", 800)
    temperature = data.get("temperature", 0.1)
    
    # Build prompt from messages
    prompt_parts = []
    for msg in messages:
        role = msg.get("role", "user")
        content = msg.get("content", "")
        if role == "system":
            prompt_parts.append(f"<|system|>\n{content}")
        elif role == "user":
            prompt_parts.append(f"<|user|>\n{content}")
        elif role == "assistant":
            prompt_parts.append(f"<|assistant|>\n{content}")
    
    prompt = "\n".join(prompt_parts)
    if prompt_parts:
        prompt += "\n<|assistant|>\n"
    
    try:
        output = llm(
            prompt,
            max_tokens=max_tokens,
            temperature=temperature,
            stop=["<|end|>"],
            echo=False,
        )
        
        response_text = output["choices"][0]["text"].strip()
        
        return jsonify({
            "choices": [{
                "message": {
                    "role": "assistant",
                    "content": response_text
                },
                "finish_reason": "stop",
                "index": 0
            }],
            "model": "qwest-v11-q4_k_m",
            "usage": {
                "prompt_tokens": output.get("usage", {}).get("prompt_tokens", 0),
                "completion_tokens": output.get("usage", {}).get("completion_tokens", 0),
                "total_tokens": output.get("usage", {}).get("total_tokens", 0)
            }
        })
        
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return jsonify({"error": str(e)}), 500


@app.route("/v1/completions", methods=["POST"])
def completions():
    """Legacy completions endpoint."""
    return chat_completions()


def main():
    parser = argparse.ArgumentParser(description="QWEST GGUF Server")
    parser.add_argument("--model", required=True, help="Path to GGUF model file")
    parser.add_argument("--port", type=int, default=8080, help="Server port")
    parser.add_argument("--ctx-size", type=int, default=2048, help="Context size")
    parser.add_argument("--gpu-layers", type=int, default=99, help="GPU layers to offload")
    args = parser.parse_args()
    
    load_model(args.model, args.ctx_size, args.gpu_layers)
    
    print(f"Starting server on port {args.port}...")
    app.run(host="0.0.0.0", port=args.port, threaded=True)


if __name__ == "__main__":
    main()