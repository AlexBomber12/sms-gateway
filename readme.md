## SMS-Gateway → Telegram
Контейнер пересылает все входящие SMS с USB-модема (Huawei E352 и подобные) в чат Telegram.  
Исходный Python-скрипт читает переменные `SMS_*` от `gammu-smsd`, поэтому файлы не парсятся.

## Запуск
git clone git@github.com:AlexBomber12/sms-gateway.git
cd sms-gateway
cp .env.example .env          # впиши токен и chat-id
docker compose up -d          # build + start

## Перезапустить
cd ~/sms-gateway
docker compose down
docker compose up -d

## Мини-чек-лист «почему SMS не доходят»
(идём сверху вниз и останавливаемся, как только пункт выполняется)

1. Есть ли порты на хосте?
ls -l /dev/ttyUSB*
Нет устройств → выдерни-вставь свисток или поставь usb-modeswitch.

2. Порт свободен?
sudo fuser -v /dev/ttyUSB0
Виден ModemManager / gpsd — sudo systemctl stop -sms-gateway && disable.

3. Конфиг чистый?
nano smsdrc; первые строки должны быть ТОЛЬКО
[gammu]
device = /dev/ttyUSB0
connection = at
без # в той же строке.

4. Compose реально пробрасывает устройства?
В docker-compose.yml у сервиса:
privileged: true
devices:
  - "${DEVICE}:${DEVICE}"
Сохрани, затем docker compose down && docker compose up -d.

5. Порты видны внутри контейнера?
docker exec -it sms-gateway ls /dev/ttyUSB*
Если пусто — п. 4 исправлен неверно (отступы) или запускаешь не тот compose-файл.

6. Модем отвечает?
docker exec -it sms-gateway gammu -c /etc/gammu-smsdrc --identify
«Error opening device» → поменяй device = /dev/ttyUSB1 или 2 и повтори.

7. Демон инициализировался?
docker logs -f sms-gateway | tail
Нужно увидеть: SMSD initialized, waiting for messages...
Если снова про ошибку открытия порта — вернись к пункту 6.

8. Сообщение ушло в Telegram?
Отправь SMS на SIM, затем посмотри лог:
sms_to_telegram.sh: Sent OK to Telegram chat_id …
Нет этой строки:
401 / 403 — неверный токен или Chat ID в .env;
«retry in 300s» — временно нет интернета.

После прохождения всех пунктов пересылка гарантированно работает.

