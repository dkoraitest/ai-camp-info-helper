# Info-Helper Skill — production-инструмент с cron

> Это **основная** реализация инфо-помощника. Запускается каждое утро в 9:00, собирает поводы касания по списку клиентов и шлёт в Telegram (или сохраняет в Markdown).
>
> Make-сценарий из [../workshop/](../workshop/) — это демонстрация архитектуры на сцене. То, что ты ставишь себе в реальную работу — здесь.

## Что это

Claude Skill, который запускается двумя способами:
1. **Интерактивно** в IDE (Claude Code, Cursor): «дай инфо по моим клиентам»
2. **По cron** через `claude -p` или `cursor -p` headless, без участия человека

## Как устроено

```
skill/
├── README.md                            (этот файл)
├── .claude/skills/info-helper/SKILL.md  (сам скилл — то, что читает Claude)
├── config/
│   ├── clients.yaml.example             (список клиентов + контекст продаж)
│   └── settings.yaml.example            (свежесть, язык, доставка, дедуп)
├── runner/
│   ├── run.sh                           (обёртка для headless / cron)
│   ├── cron.example                     (crontab пример)
│   ├── launchd.plist.example            (macOS launchd)
│   └── systemd.example                  (Linux systemd)
├── delivery/
│   ├── telegram.sh                      (fallback shell-доставка)
│   └── README.md                        (как настроить бота)
├── examples/
│   └── sample-output.md                 (как выглядит отчёт)
├── cache/                               (создаётся автоматом, в .gitignore)
├── logs/                                (создаётся автоматом, в .gitignore)
└── reports/                             (создаётся автоматом, в .gitignore)
```

## Установка за 10 минут

### 1. Клонируй репо и зайди в skill-папку

```bash
cd info-helper/skill
```

### 2. Скопируй конфиги

```bash
cp config/clients.yaml.example config/clients.yaml
cp config/settings.yaml.example config/settings.yaml
```

Открой `clients.yaml`, замени список на свои 5-50 ключевых клиентов и контекст продаж.

### 3. Положи API ключи

```bash
cat > .env <<'EOF'
ANTHROPIC_API_KEY=sk-ant-...
TELEGRAM_BOT_TOKEN=7123456789:AAH...
TELEGRAM_CHAT_ID=123456789
EOF
chmod 600 .env
```

### 4. Установи Claude CLI

```bash
# https://claude.ai/claude-code
curl -fsSL claude.ai/install.sh | bash
```

(или Cursor CLI, скилл умеет работать через оба)

### 5. Тестовый прогон

```bash
./runner/run.sh --dry-run --client "АкмеЛогистикс"
```

Должен вывести Markdown-отчёт в stdout. Если ок — реальный прогон:

```bash
./runner/run.sh --once
```

В `reports/` появится файл, в Telegram — сообщение.

### 6. Поставь на cron

См. [runner/README.md](runner/README.md) → раздел про cron / launchd / systemd. Расписание по умолчанию: **9:00 по будням Asia/Almaty**.

## Как работает (упрощённо)

```
[cron 9:00]
    ↓
[run.sh]
    ↓
[claude -p "/info-helper run from config"]
    ↓
SKILL:
  1. читает config/clients.yaml
  2. для каждой компании: WebSearch + WebFetch (новости, ЛПР, вакансии)
  3. фильтр (свежесть ≤ 7 дней, конкретика, дедуп через cache/)
  4. формулирует hook + opening_line на русском
  5. пишет reports/info-helper-{дата}.md
  6. шлёт в Telegram (если включено в settings)
  7. обновляет cache/sent-events.json
```

## Чем отличается от Make-сценария

| | Make (`../workshop/`) | Claude Skill (`./`) |
|---|---|---|
| Сложность | Low-code, drag-and-drop | Конфиг + shell |
| Стоимость | $9/мес Make + API | Только API (Anthropic, ~$3-10/мес) |
| Гибкость | Ограничена нодами Make | Полная — Claude умеет всё, что в скилле |
| Дедуп | Вручную через Google Sheet | Встроена через `cache/` |
| Тон сообщения | Зафиксирован в промпте | Skill умеет адаптировать под контекст клиента |
| KZ-этикет | В промпте | В скилле + ссылка на enrich-and-pitch skill |
| Multi-source (LinkedIn, X) | По 1 ноде на источник | Автоопределение по env-переменным |
| Развёртывание у клиента | Нужен Make-аккаунт | Только `git clone` + `.env` |
| Кому подходит | Менеджер без программистов | Команды, где есть хотя бы один Claude-юзер |

## Roadmap (что добавим, если кейс зайдёт)

- [ ] CRM-источник клиентов: `hubspot`, `amocrm`, `bitrix24` (читай в `config/clients.yaml` секцию `crm.source`)
- [ ] Многоканальная доставка: разные клиенты → разным менеджерам
- [ ] Слайд по аналитике: каких клиентов забывают
- [ ] Auto-feedback loop: какие поводы привели к звонку — учитываем приоритет в скоринге

## Контакты

Telegram: @dkorobovtsev
Email: dkor.aitest@gmail.com

Если кейс реально полетел — напиши. Соберём кастомную доставку.
