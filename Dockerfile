# Dockerfile — QWEST GGUF Model Server on RunPod (CUDA 12.4)
# Uses nvidia/cuda base from Docker Hub (public, no auth required)
# Installs llama-cpp-python with CUDA support

FROM nvidia/cuda:12.4.0-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Install Python and tools
RUN apt-get update && apt-get install -y \
    python3.11 \
    python3.11-venv \
    python3-pip \
    curl \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Create venv
RUN python3.11 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install llama-cpp-python with CUDA/BLAS support
RUN /opt/venv/bin/pip install --no-cache-dir \
    llama-cpp-python \
    --extra-index-url=https://abetlen.github.io/llama-cpp-python/whl/cublas

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

EXPOSE 8080

CMD ["/app/startup.sh"]