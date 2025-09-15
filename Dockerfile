FROM python:3.12-slim AS base

# Install system dependencies in one layer and clean up in same layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    libgomp1 \
    libgthread-2.0-0 \
    ffmpeg \
    libfontconfig1 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /var/cache/apt/archives/*

# Set work directory
WORKDIR /app

COPY ./ .
RUN pip install --no-cache-dir -r requirements.txt && \
    find /usr/local/lib/python3.12/site-packages -name "*.pyc" -delete && \
    find /usr/local/lib/python3.12/site-packages -name "__pycache__" -type d -exec rm -rf {} + || true

FROM base AS model-deps
ARG MODEL_NAME

# Copy model requirements and install
COPY src/lib/model/${MODEL_NAME}/requirements.txt src/lib/model/${MODEL_NAME}/requirements.txt
RUN pip install --no-cache-dir -r src/lib/model/${MODEL_NAME}/requirements.txt && \
    find /usr/local/lib/python3.12/site-packages -name "*.pyc" -delete && \
    find /usr/local/lib/python3.12/site-packages -name "__pycache__" -type d -exec rm -rf {} + || true

FROM model-deps AS final

# Create non-root user for security
RUN useradd --create-home --shell /bin/bash appuser && \
    chown -R appuser:appuser /app
USER appuser

# Copy application code
COPY --chown=appuser:appuser . .

# Expose port
EXPOSE 8000

# Add health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/info || exit 1

ENV MODEL_NAME=${MODEL_NAME}
# Use exec form for better signal handling
CMD ["fastapi", "run", "src/main.py", "--host", "0.0.0.0", "--port", "8000"]