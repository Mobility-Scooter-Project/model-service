FROM python:3.12-slim AS base

# install poetry
ENV POETRY_HOME=/opt/poetry
RUN apt-get update && apt-get install -y curl && \
	curl -sSL https://install.python-poetry.org | POETRY_HOME=$POETRY_HOME python3 - && \
	$POETRY_HOME/bin/poetry --version && \
	apt-get remove -y curl && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*
ENV PATH="$POETRY_HOME/bin:$PATH"
ENV POETRY_VIRTUALENVS_CREATE=false

# set work directory
WORKDIR /app
COPY pyproject.toml poetry.lock ./

FROM base AS pytorch-builder
COPY --from=base /app/pyproject.toml /app/pyproject.toml
COPY --from=base /app/poetry.lock /app/poetry.lock
RUN poetry install --with pytorch

FROM pytorch-builder AS pytorch
ARG MODEL_NAME
COPY --from=base /app /app/
COPY . .

RUN poetry install --with ${MODEL_NAME}

EXPOSE 8000
CMD ["poetry", "run", "fastapi", "run", "src/main.py"]