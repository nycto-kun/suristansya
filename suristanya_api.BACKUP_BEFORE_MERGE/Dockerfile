FROM python:3.10-slim

WORKDIR /app

# System libs for OpenCV
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 5000

# Gunicorn: 2 workers, 120s timeout for model inference
CMD ["gunicorn", "--bind", "0.0.0.0:5000", \
     "--workers", "2", "--timeout", "120", "--access-logfile", "-", \
     "app:app"]