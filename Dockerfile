FROM python:3.12-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gammu gammu-smsd usbutils procps && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

WORKDIR /app
COPY . /app
RUN chmod +x /app/start.sh

ENTRYPOINT ["/app/start.sh"]
