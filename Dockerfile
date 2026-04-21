FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS base

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_TOOL_BIN_DIR=/usr/local/bin

WORKDIR /app
    
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=requirements.txt,target=requirements.txt \
    uv venv && uv pip install -r requirements.txt

FROM base AS final
ARG MODEL_NAME
ARG MODEL_ACCELERATOR=cpu

WORKDIR /app

RUN apt-get update \
    && if [ "$MODEL_NAME" = "whisperx" ]; then \
         apt-get install -y --no-install-recommends ffmpeg; \
       elif [ "$MODEL_NAME" = "yolo" ]; then \
         apt-get install -y --no-install-recommends libglib2.0-0; \
       fi \
    && rm -rf /var/lib/apt/lists/*

COPY --from=base /app/.venv /app/.venv

COPY ./src ./src

RUN --mount=type=cache,target=/root/.cache/pip \
    if [ "$MODEL_ACCELERATOR" = "cpu" ]; then \
         /app/.venv/bin/pip install \
           --index-url https://download.pytorch.org/whl/cpu \
           --extra-index-url https://pypi.org/simple \
           -r src/model/${MODEL_NAME}/requirements.txt \
           -r src/model/${MODEL_NAME}/requirements.cpu.txt; \
       elif [ "$MODEL_ACCELERATOR" = "gpu" ]; then \
         /app/.venv/bin/pip install \
           -r src/model/${MODEL_NAME}/requirements.txt \
           -r src/model/${MODEL_NAME}/requirements.gpu.txt; \
       else \
         echo "Unsupported MODEL_ACCELERATOR: $MODEL_ACCELERATOR" >&2; \
         exit 1; \
       fi

RUN mkdir -p /app/.cache /app/.cache/yolo /app/.config \
    && chmod -R 777 /app/.cache /app/.config

ENV TORCH_HOME=/app/.cache/torch \
    HF_HOME=/app/.cache/huggingface \
    YOLO_CONFIG_DIR=/app/.cache/yolo \
    MODEL_CACHE_DIR=/app/.cache

ENV PATH="/app/.venv/bin:$PATH"
ENV MODEL_NAME=${MODEL_NAME}

ENTRYPOINT []

CMD ["fastapi", "run", "src/main.py", "--host", "0.0.0.0", "--port", "8000"]
