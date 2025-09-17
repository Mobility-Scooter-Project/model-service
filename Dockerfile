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

WORKDIR /app

COPY --from=base /app/.venv /.venv

COPY ./src ./src

RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install -r src/model/${MODEL_NAME}/requirements.txt

ENV PATH="/app/.venv/bin:$PATH"
ENV MODEL_NAME=${MODEL_NAME}

ENTRYPOINT []

CMD ["fastapi", "run", "src/main.py", "--host", "0.0.0.0", "--port", "8000"]