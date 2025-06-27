FROM python:3.12-slim
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gammu gammu-smsd usbutils procps && \
    rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir requests
WORKDIR /app
COPY start.sh /app/start.sh
COPY on_receive.py /app/on_receive.py
RUN chmod +x /app/start.sh
ENTRYPOINT ["/app/start.sh"]
