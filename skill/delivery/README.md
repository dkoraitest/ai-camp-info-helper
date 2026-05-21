# Delivery — куда отправлять готовый отчёт

Скилл сам умеет писать Markdown-файл в `reports/`. Доставка наружу — опциональна и настраивается в `config/settings.yaml` секцией `delivery`.

## Telegram

### 1. Создай бота

1. В Telegram открой `@BotFather`.
2. Команда `/newbot` → дай имя (например, `ИнфоПомощник по клиентам · Дмитрий`).
3. Сохрани **bot token** — это длинная строка вида `7123456789:AAH...`.

### 2. Узнай свой chat_id

Вариант A — личные сообщения:
1. Открой свой только что созданный бот, нажми **Start**.
2. Открой в браузере: `https://api.telegram.org/bot<TOKEN>/getUpdates`
3. Найди `"chat": {"id": 123456789, ...}` — это твой chat_id.

Вариант B — групповой чат:
1. Добавь бота в группу.
2. Напиши что-нибудь в группу.
3. Открой `getUpdates` (как выше).
4. chat_id у группы будет **отрицательный**, типа `-1001234567890`.

Альтернатива: бот `@RawDataBot` — добавь в чат, он сразу пришлёт `chat_id`.

### 3. Положи в .env

```bash
TELEGRAM_BOT_TOKEN=7123456789:AAH...
TELEGRAM_CHAT_ID=123456789
```

И в `config/settings.yaml`:
```yaml
delivery:
  telegram:
    enabled: true
    bot_token: ${TELEGRAM_BOT_TOKEN}
    chat_id: ${TELEGRAM_CHAT_ID}
    chunk_size_chars: 3800
```

### 4. Тест

```bash
cd info-helper/skill
echo -e "# Test\n\nЕсли видишь это в Telegram — всё работает." > /tmp/test-report.md
./delivery/telegram.sh /tmp/test-report.md
```

В Telegram должно прийти сообщение.

### Возможные проблемы

- **«Forbidden: bot was blocked»** — ты не нажал `/start` своему боту. Открой бот в Telegram, нажми Start.
- **«Bad Request: chat not found»** — неверный `chat_id`. Перепроверь через `getUpdates`.
- **«Message is too long»** — увеличь `chunk_size_chars` обратно к 3800 или ниже. Telegram-лимит 4096.

## Slack (TODO)

В `settings.yaml` секция `slack.webhook_url`. Доставка через Incoming Webhook URL Slack-приложения.

См. [slack-setup.md](slack-setup.md) (создай по аналогии — простая POST-нода).

## Email (TODO)

В `settings.yaml` секция `email`. Доставка через SMTP. Используется в команде, где менеджеры не сидят в Telegram.

## Сравнение каналов

| Канал | Плюсы | Минусы |
|---|---|---|
| Telegram | Мгновенно, мобильно, читают точно | Нужен бот + chat_id |
| Slack | Если команда уже в Slack | Корпоративные ограничения |
| Email | Универсально | Менеджер не откроет сразу утром |
| Markdown only | Просто файл | Никто не зайдёт смотреть |

**Рекомендация:** Telegram + Markdown-файл (для архива). Slack — если команда там живёт.
