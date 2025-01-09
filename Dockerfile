FROM python:3.10
WORKDIR /app
COPY requirements.txt requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
# Uvicorn will handle reloading when files change via the mounted volume
COPY . ./
EXPOSE 8000