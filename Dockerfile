# Stage 1: Base image with common dependencies
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04 as base

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1 

# Install Python, git and other necessary tools
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    git \
    wget

# Clean up to reduce image size
RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Clone ComfyUI repository
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /comfyui

# Change working directory to ComfyUI
WORKDIR /comfyui

# Install ComfyUI dependencies
RUN pip3 install --upgrade --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121 \
    && pip3 install --upgrade -r requirements.txt

# Install runpod
RUN pip3 install runpod requests

# Support for the network volume
ADD src/extra_model_paths.yaml ./

# Go back to the root
WORKDIR /

# Add the start and the handler
ADD src/start.sh src/rp_handler.py test_input.json ./
RUN chmod +x /start.sh

# Stage 2: Download models
FROM base as downloader

ARG HUGGINGFACE_ACCESS_TOKEN
ARG MODEL_TYPE

# Change working directory to ComfyUI
WORKDIR /comfyui

RUN mkdir -p models/checkpoints models/upscale_models

# Download checkpoints/vae/LoRA to include in image based on model type
RUN wget -O models/checkpoints/DreamShaperXL_Turbo_SFWdpmppSde_half_pruned.safetensors https://huggingface.co/Lykon/DreamShaper/resolve/main/DreamShaperXL_Turbo_SFWdpmppSde_half_pruned.safetensors

# Download Upscale model
RUN wget -O models/upscale_models/4x-UltraSharp.pth https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth

# Install custom nodes
RUN git clone https://github.com/john-mnz/ComfyUI-Inspyrenet-Rembg.git /comfyui/custom_nodes/ComfyUI-Inspyrenet-Rembg
WORKDIR /comfyui/custom_nodes/ComfyUI-Inspyrenet-Rembg
RUN pip3 install -r requirements.txt

# Install custom nodes
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git /comfyui/custom_nodes/ComfyUI-Manager
WORKDIR /comfyui/custom_nodes/ComfyUI-Manager
RUN pip3 install -r requirements.txt

# Stage 3: Final image
FROM base as final

# Copy models from stage 2 to the final image
COPY --from=downloader /comfyui/models /comfyui/models

# Start the container
CMD /start.sh