# Runner — запуск info-helper по cron

`run.sh` — обёртка, которая запускает скилл info-helper в headless-режиме через Claude Code CLI или Cursor CLI. Дизайн под cron-расписание «каждое утро в 9:00».

## Что внутри

| Файл | Назначение |
|---|---|
| [run.sh](run.sh) | Точка входа. Сама вызывает `claude -p` или `cursor -p` с инструкцией скиллу. |
| [cron.example](cron.example) | Пример строки для `crontab -e` (Linux, macOS legacy). |
| [launchd.plist.example](launchd.plist.example) | Пример plist для macOS launchd (рекомендуется на маках). |
| [systemd.example](systemd.example) | Пример service + timer для Linux с systemd. |

## Предварительные шаги

### 1. Установи Claude Code CLI или Cursor CLI

```bash
# Claude Code CLI
curl -fsSL claude.ai/install.sh | bash
# Или с офсайта: https://claude.ai/claude-code

# Cursor CLI
# https://cursor.sh/cli
```

Проверь:
```bash
claude --version
# или
cursor-agent --version
```

### 2. Заведи Anthropic API key

`console.anthropic.com` → API Keys → Create.

### 3. Положи ключи и конфиги

```bash
cd info-helper/skill

# Конфиги
cp config/clients.yaml.example config/clients.yaml
cp config/settings.yaml.example config/settings.yaml

# Env (.env в корне skill/)
cat > .env <<'EOF'
ANTHROPIC_API_KEY=sk-ant-...
# Опционально:
APIFY_API_KEY=apify_api_...
XAI_API_KEY=xai-...
TELEGRAM_BOT_TOKEN=...
TELEGRAM_CHAT_ID=...
EOF

# Защити .env
chmod 600 .env
```

`.env` уже в `.gitignore` корня репо. Если нет — добавь.

### 4. Отредактируй `config/clients.yaml`

Под себя: вставь свои реальные компании и контекст продаж.

### 5. Тестовый прогон

```bash
cd info-helper/skill
./runner/run.sh --dry-run --client "АкмеЛогистикс"
```

Должен вывести в stdout Markdown-отчёт по одной компании без сохранения файла и без Telegram.

Если ОК — запусти полный прогон:
```bash
./runner/run.sh --once
```

В `reports/info-helper-{сегодня}.md` появится отчёт.

## Установка cron (macOS / Linux legacy)

```bash
crontab -e
```

Добавь строку (см. также [cron.example](cron.example)):

```
0 9 * * 1-5 cd /full/path/to/info-helper/skill && ./runner/run.sh >> logs/cron.log 2>&1
```

Расшифровка:
- `0 9 * * 1-5` — в 9:00 каждый будний день
- `cd /full/path/...` — обязательно полный путь (cron работает не из твоей домашки)
- `>> logs/cron.log 2>&1` — лог пишется поверх (для отладки)

## Установка launchd (macOS — рекомендуется)

Cron на macOS работает, но launchd — нативный способ.

1. Открой [launchd.plist.example](launchd.plist.example), поменяй `PROGRAM_ARGUMENTS` и пути под себя.
2. Скопируй в `~/Library/LaunchAgents/com.aisurfers.info-helper.plist`.
3. Загрузи:
   ```bash
   launchctl load ~/Library/LaunchAgents/com.aisurfers.info-helper.plist
   ```
4. Проверь:
   ```bash
   launchctl list | grep info-helper
   ```

Для остановки:
```bash
launchctl unload ~/Library/LaunchAgents/com.aisurfers.info-helper.plist
```

## Установка systemd (Linux серверы)

См. [systemd.example](systemd.example). Создай два файла:

- `/etc/systemd/system/info-helper.service`
- `/etc/systemd/system/info-helper.timer`

Затем:
```bash
sudo systemctl enable --now info-helper.timer
sudo systemctl list-timers --all | grep info-helper
```

## Отладка

### Cron запустился, но ничего не сделал
- Проверь `logs/run-*.log` и `logs/cron.log`.
- Cron работает в minimal env — `PATH` может не содержать `claude`. В `cron.example` явно прописан `PATH`.

### `claude` не находит skill
- Скилл должен лежать в `info-helper/skill/.claude/skills/info-helper/SKILL.md` относительно cwd.
- `run.sh` делает `cd "$SKILL_DIR"` перед запуском CLI — это важно.

### Отчёт пришёл пустой
- Скорее всего, кэш `cache/sent-events.json` уже содержит все события — скилл правильно дедупит.
- Очисти кэш: `rm cache/sent-events.json` → запусти заново.
- Или уменьши `dedup.ttl_days` в settings.yaml.

### Telegram не доходит
- Проверь, что бот стартовал у тебя в Telegram (нажми `/start` своему боту, иначе он не имеет права слать тебе).
- `chat_id` — числовое значение (для группы — отрицательное). Получи через `@RawDataBot` или `getUpdates`.
- См. [delivery/telegram.sh](../delivery/telegram.sh) и [delivery/README.md](../delivery/README.md).

## Production checklist

- [ ] `.env` с правильными ключами, mode 600
- [ ] `config/clients.yaml` с реальными компаниями
- [ ] `config/settings.yaml` с включённой Telegram-доставкой
- [ ] Тестовый прогон `--dry-run` прошёл
- [ ] Cron / launchd / systemd установлен
- [ ] Логи ротируются (либо вручную раз в неделю, либо через logrotate)
- [ ] Кэш `cache/sent-events.json` живёт между запусками (не очищается случайно)
- [ ] Через 3 дня — проверь, что каждое утро приходит сообщение
