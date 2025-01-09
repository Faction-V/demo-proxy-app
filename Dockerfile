FROM python:3.10
WORKDIR /app
COPY . /app

# Install dependencies if required (e.g., requirements.txt)
RUN pip install -r requirements.txt

# Set the default command to run your application
CMD ["python", "app.py"]
