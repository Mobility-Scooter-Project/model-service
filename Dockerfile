ARG MODEL_NAME

FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS base
ARG MODEL_NAME

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_MAX_THREADS=1 \
    XDG_CACHE_HOME=/app/.cache \
    XDG_CONFIG_HOME=/app/.config

WORKDIR /app

RUN set -eux; \
    apt-get update; \
    runtime_deps="ca-certificates libgomp1"; \
    case "${MODEL_NAME}" in \
      yolo) runtime_deps="${runtime_deps} libxcb1 libglib2.0-0 libgl1" ;; \
      whisperx) runtime_deps="${runtime_deps} ffmpeg" ;; \
    esac; \
    apt-get install -y --no-install-recommends ${runtime_deps}; \
    rm -rf /var/lib/apt/lists/*
    
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=requirements.txt,target=requirements.txt \
    uv venv && uv pip install -r requirements.txt

FROM base AS final
ARG MODEL_NAME

WORKDIR /app

COPY --from=base /app/.venv /.venv

COPY ./src ./src

RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install -r src/model/${MODEL_NAME}/requirements.txt

RUN mkdir -p /app/.cache/torch /app/.cache/huggingface /app/.cache/yolo /app/.config /tmp/whisperx \
    && chmod -R 777 /app/.cache /app/.config /tmp/whisperx

ENV TORCH_HOME=/app/.cache/torch \
    HF_HOME=/app/.cache/huggingface \
    YOLO_CONFIG_DIR=/app/.cache/yolo \
    MODEL_CACHE_DIR=/app/.cache \
    PATH="/app/.venv/bin:$PATH" \
    MODEL_NAME=${MODEL_NAME}

ENTRYPOINT []

CMD ["fastapi", "run", "src/main.py", "--host", "0.0.0.0", "--port", "8000"]
