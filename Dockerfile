FROM python:3.12-slim AS base

# install system dependencies for OpenCV and other libraries
RUN apt-get update && apt-get install -y \
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
    && rm -rf /var/lib/apt/lists/*

# install poetry
ENV POETRY_HOME=/opt/poetry \
    POETRY_NO_INTERACTION=1 \
    POETRY_VIRTUALENVS_IN_PROJECT=1 \
    POETRY_VIRTUALENVS_CREATE=1 \
    POETRY_CACHE_DIR=/tmp/poetry_cache

RUN curl -sSL https://install.python-poetry.org | POETRY_HOME=$POETRY_HOME python3 - && \
	$POETRY_HOME/bin/poetry --version
ENV PATH="$POETRY_HOME/bin:$PATH"

# set work directory
WORKDIR /app

# Copy dependency files
COPY pyproject.toml poetry.lock ./ 

RUN poetry install --no-root && rm -rf $POETRY_CACHE_DIR

FROM base AS model-deps
ARG MODEL_NAME

COPY src/lib/model/${MODEL_NAME}/requirements.txt src/lib/model/${MODEL_NAME}/requirements.txt
RUN pip install -r src/lib/model/${MODEL_NAME}/requirements.txt --no-cache-dir

FROM model-deps AS final
# copy project files
COPY . .

CMD ["poetry", "run", "fastapi", "run", "src/main.py" ]