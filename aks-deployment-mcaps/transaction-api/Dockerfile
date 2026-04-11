FROM python:3.11-slim AS builder
WORKDIR /install
COPY requirements.txt .
RUN pip install --prefix=/install/deps --no-cache-dir -r requirements.txt

FROM python:3.11-slim
WORKDIR /app
COPY --from=builder /install/deps /usr/local
COPY app.py .

RUN useradd -r -u 1000 appuser
USER appuser

EXPOSE 5000
CMD ["python", "app.py"]
