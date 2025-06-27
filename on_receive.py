#!/usr/bin/env python3
import os, re, html, requests, time, sys

bot  = os.getenv("TELEGRAM_BOT_TOKEN")
chat = os.getenv("TELEGRAM_CHAT_ID")

parts = int(os.getenv("SMS_MESSAGES", "1"))
num   = os.getenv("SMS_1_NUMBER", "unknown").strip()

txt = "\n".join(
    os.getenv(f"SMS_{i}_TEXT", "").rstrip()
    for i in range(1, parts + 1)
).lstrip()

txt = re.sub(r"\n(?!\n)", " ", txt)
txt = re.sub(r" {2,}", " ", txt)
if not txt:
    txt = "(empty)"

payload = {
    "chat_id": chat,
    "text": f"<b>{html.escape(num)}</b>\n{html.escape(txt[:4096])}",
    "parse_mode": "HTML",
}

for _ in range(120):
    try:
        requests.post(
            f"https://api.telegram.org/bot{bot}/sendMessage",
            json=payload,
            timeout=10,
        ).raise_for_status()
        break
    except Exception:
        time.sleep(30)
else:
    sys.exit(1)
