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
ENV POETRY_HOME=/opt/poetry
RUN curl -sSL https://install.python-poetry.org | POETRY_HOME=$POETRY_HOME python3 - && \
	$POETRY_HOME/bin/poetry --version
ENV PATH="$POETRY_HOME/bin:$PATH"
ENV POETRY_VIRTUALENVS_CREATE=false

# set work directory
WORKDIR /app
COPY pyproject.toml poetry.lock ./
RUN poetry install --no-root

FROM base AS pytorch-builder
COPY --from=base /app/pyproject.toml /app/pyproject.toml
COPY --from=base /app/poetry.lock /app/poetry.lock
RUN poetry install --only pytorch

FROM pytorch-builder AS pytorch
ARG MODEL_NAME
COPY --from=base /app /app/
COPY . .

RUN poetry install --only ${MODEL_NAME}
ENV MODEL_NAME=${MODEL_NAME}

EXPOSE 8000
CMD ["fastapi", "run", "src/main.py"]