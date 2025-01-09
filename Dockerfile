FROM python:3.10
COPY . ./
WORKDIR /app

COPY requirements.txt requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Uvicorn will handle reloading when files change via the mounted volume
EXPOSE 8000