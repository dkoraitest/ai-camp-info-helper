# Telegram Setup Wizard — пошаговая настройка из чата

Эта инструкция следует Phase 5 интерактивного workflow. Skill ведёт пользователя через настройку шаг за шагом, не заставляя его читать документацию.

## Шаг 1: Создать бота

Скилл говорит:
```
Открой @BotFather в Telegram (https://t.me/BotFather) и пришли ему /newbot.
Он спросит:
  - Имя бота (любое — например, «Инфо-помощник Дмитрия»)
  - Username бота (должен заканчиваться на _bot, например «dkor_info_helper_bot»)

В конце получишь токен — длинная строка вида:
  7123456789:AAHfg7yJk2sLpQrTvBnMcXeR3iOpAsDfGh

Скопируй её и пришли мне сюда.
```

Ждёт ввод. Принимает строку, валидирует regex `^\d{8,12}:[A-Za-z0-9_-]{20,}$`. Если не подходит — просит повторить.

## Шаг 2: Узнать chat_id

Когда токен получен:
```
Спасибо. Теперь нужен твой chat_id — куда я буду слать сообщения.

Самый простой способ:
  1. Открой только что созданного бота в Telegram (поищи его по username)
  2. Нажми кнопку Start (или напиши /start)
  3. Открой в браузере: https://api.telegram.org/bot<ТВОЙ_ТОКЕН>/getUpdates
     (заменив <ТВОЙ_ТОКЕН> на длинную строку, которую ты только что прислал)
  4. Найди в ответе блок:
       "chat": {
         "id": 123456789,
         ...
       }
     Число после "id" — твой chat_id. Скопируй и пришли сюда.

Если хочешь чтобы сообщения шли в групповой чат (например, рабочей команде):
  - Добавь бота в группу
  - Напиши что-нибудь в группу
  - Снова открой getUpdates — в этом случае chat_id будет отрицательный
    (например, -1001234567890)
```

Ждёт ввод. Валидирует regex `^-?\d{6,15}$`.

## Шаг 3: Тестовая отправка

Когда chat_id получен — скилл отправляет тестовое сообщение:

```bash
curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  -d "chat_id=${CHAT_ID}" \
  --data-urlencode "text=✓ Инфо-помощник подключён. Завтра в 9:00 пришлю первые поводы для касания." \
  -d "parse_mode=Markdown"
```

Парсит ответ:
- HTTP 200 + `"ok":true` → успех
- HTTP 403 «Forbidden: bot was blocked» → пользователь не нажал /start
- HTTP 400 «chat not found» → неверный chat_id
- HTTP 401 → неверный токен

Сообщает результат:
```
✓ Тестовое сообщение отправлено. Проверь Telegram — пришло?

Если да — скажи «да», и я сохраню настройки + поставлю cron на 9:00 каждый будний день.
Если нет — посмотрим что не так.
```

## Шаг 4: Сохранение настроек

Когда пользователь подтверждает:

1. **Сохранить `.env` в корне репо** (mode 600):
   ```
   TELEGRAM_BOT_TOKEN=7123456789:AAH...
   TELEGRAM_CHAT_ID=123456789
   ANTHROPIC_API_KEY=<если уже есть; иначе попросить>
   ```

2. **Обновить `config/settings.yaml`** — секцию `delivery.telegram`:
   ```yaml
   delivery:
     telegram:
       enabled: true
       bot_token: ${TELEGRAM_BOT_TOKEN}
       chat_id: ${TELEGRAM_CHAT_ID}
       chunk_size_chars: 3800
   ```

3. **Проверить, что `config/clients.yaml` существует** (создан в Phase 2 этого workflow). Если нет — создать из тех клиентов, что обсуждали в этой сессии.

## Шаг 5: Установка cron / launchd

Скилл показывает 3 варианта (выбор за пользователем):

```
Cron — когда запускать?

Варианты:
A) macOS / Linux desktop — установим через launchd (macOS) или cron (Linux)
B) Облачный сервер — дам тебе строку для crontab
C) Make.com / n8n — дам blueprint, ты сам импортируешь

Что выбираешь?
```

**Вариант A — macOS launchd:**
1. Сгенерировать `~/Library/LaunchAgents/com.aisurfers.info-helper.plist` из `runner/launchd.plist.example`, подставив пути.
2. Загрузить: `launchctl load ~/Library/LaunchAgents/com.aisurfers.info-helper.plist`
3. Проверить: `launchctl list | grep info-helper`

**Вариант A — Linux cron:**
1. Показать строку для `crontab -e`:
   ```
   0 9 * * 1-5 cd /full/path/to/ai-camp-info-helper && ./runner/run.sh >> logs/cron.log 2>&1
   ```
2. Сказать «вставь это в `crontab -e`».

**Вариант B — облачный сервер:**
1. Дать ту же crontab-строку.
2. Сказать «также убедись что на сервере установлен Claude Code CLI и есть ANTHROPIC_API_KEY в env».

**Вариант C — Make.com:**
1. Сказать «в `workshop/make-blueprint.json` лежит готовый сценарий — импортируй».

## Финал

```
Готово.

✓ Бот создан и подключён
✓ .env сохранён (mode 600, в .gitignore)
✓ config/settings.yaml обновлён
✓ Cron поставлен на 09:00 будни (Asia/Almaty)

Следующее сообщение придёт завтра в 9:00. Если хочешь сейчас прогнать тест:
  ./runner/run.sh --once

Если захочешь изменить клиентов — открой config/clients.yaml.
Если потеряется доставка — посмотри logs/cron.log.
```

## Если пользователь говорит «пока без Telegram»

```
Хорошо. Отчёт сохранится в reports/info-helper-<дата>.md как Markdown.

Telegram можно подключить позже — просто скажи «настрой Telegram» и я проведу через шаги.
```

Сохраняет `config/clients.yaml` (если ещё не сохранён), но в `config/settings.yaml` оставляет `delivery.telegram.enabled: false`.

## Edge cases

### Пользователь не понимает где взять @BotFather
Дай прямую ссылку: https://t.me/BotFather — она открывает Telegram (мобильный или desktop) и сразу ведёт к боту.

### Пользователь прислал токен без двоеточия
Это значит он скопировал только цифровую часть. Скажи: «токен должен содержать двоеточие и быть длиннее, перепроверь — это вся строка которую прислал @BotFather».

### Пользователь не может открыть getUpdates URL
Альтернатива: бот `@userinfobot` — добавь в чат, он сразу пришлёт `id`.

### Пользователь хочет slack/email вместо Telegram
В Phase 5 скажи «Telegram сейчас, slack/email — позже через config/settings.yaml (там есть placeholder секции)».
