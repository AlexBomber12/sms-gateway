## SMS-Gateway → Telegram

Контейнер пересылает все входящие SMS с USB-модема (Huawei E352 и подобные) в чат Telegram.  
Исходный Python-скрипт читает переменные `SMS_*` от `gammu-smsd`, поэтому файлы не парсятся.

### Запуск

git clone git@github.com:AlexBomber12/sms-gateway.git
cd sms-gateway
cp .env.example .env          # впиши токен и chat-id
docker compose up -d          # build + start
