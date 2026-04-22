FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS base

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_TOOL_BIN_DIR=/usr/local/bin

WORKDIR /app

COPY requirements.txt ./requirements.txt

RUN --mount=type=cache,target=/root/.cache/uv \
    uv venv && uv pip install -r requirements.txt

FROM base AS final
ARG MODEL_NAME

WORKDIR /app

RUN apt-get update \
    && if [ "$MODEL_NAME" = "whisperx" ]; then \
         apt-get install -y --no-install-recommends ffmpeg; \
       elif [ "$MODEL_NAME" = "yolo" ]; then \
         apt-get install -y --no-install-recommends libglib2.0-0; \
       fi \
    && rm -rf /var/lib/apt/lists/*

COPY --from=base /app/.venv /app/.venv

COPY src/model/${MODEL_NAME}/requirements.txt /tmp/model-requirements.txt

RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install \
      --python /app/.venv/bin/python \
      --torch-backend auto \
      -r /tmp/model-requirements.txt

COPY src/__init__.py src/main.py src/config.py ./src/
COPY src/jobs ./src/jobs
COPY src/lib ./src/lib
COPY src/storage ./src/storage
COPY src/utils ./src/utils
COPY src/webhooks ./src/webhooks
COPY src/worker ./src/worker
COPY src/model/__init__.py ./src/model/__init__.py
COPY src/model/catalog.py ./src/model/catalog.py
COPY src/model/${MODEL_NAME} ./src/model/${MODEL_NAME}

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
