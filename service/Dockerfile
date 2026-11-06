
# Stage 1: Build dependencies
FROM python:3.12-slim-bookworm AS builder

WORKDIR /build

RUN python -m venv /opt/venv

ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt


# Stage 2: Runtime image
FROM python:3.12-slim-bookworm AS runtime

ENV PATH="/opt/venv/bin:$PATH"
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

RUN useradd --create-home --uid 10001 appuser

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY --chown=appuser:appuser app.py .

USER 10001

EXPOSE 8080

CMD ["python", "app.py"]
