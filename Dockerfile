FROM python:3.12-slim

ARG INSTALL_DEV_DEPS="false"

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        cron usb-modeswitch usbutils gammu gammu-smsd procps tini \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN usermod -a -G dialout root

COPY requirements.txt /tmp/requirements.txt
COPY requirements-dev.txt /tmp/requirements-dev.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt \
    && if [ "$INSTALL_DEV_DEPS" = "true" ]; then \
        pip install --no-cache-dir -r /tmp/requirements-dev.txt; \
    fi

WORKDIR /app
ENV PYTHONPATH="/app:${PYTHONPATH}"
COPY . /app
RUN pip install --no-cache-dir -e .
RUN chmod +x /app/start.sh
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh
COPY smsgw-watchdog.sh /usr/local/bin/
RUN chmod 755 /usr/local/bin/smsgw-watchdog.sh
COPY smsgw-watchdog.cron /etc/cron.d/
RUN chmod 644 /etc/cron.d/smsgw-watchdog.cron && crontab /etc/cron.d/smsgw-watchdog.cron
ENTRYPOINT ["/usr/bin/tini","--","./entrypoint.sh"]
