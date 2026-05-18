FROM python:3.11-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DEFAULT_TIMEOUT=300 \
    PIP_RETRIES=10 \
    KEMASAN_MODEL_DIR=/models/outputs

RUN apt-get update && apt-get install -y \
    libglib2.0-0 \
    libsm6 \
    libgl1 \
    libxrender1 \
    libxext6 \
    && rm -rf /var/lib/apt/lists/*

COPY label-gizi-service/requirements.txt /app/requirements.txt
RUN python -m pip install --upgrade pip setuptools wheel \
    && pip install --no-cache-dir --default-timeout=300 --retries 10 -r requirements.txt

COPY label-gizi-service /app
COPY outputs /models/outputs

EXPOSE 5060

CMD ["python", "app.py"]
