---
name: info-helper
description: Use when the user wants to get daily touch reasons (поводы для касания) for one or several B2B clients. Researches each company via WebSearch + WebFetch for the past 7-30 days, summarizes into 3-5 concrete touch reasons with hooks and ready opening lines in Russian, and optionally delivers via Telegram. Designed to run headless on a cron schedule. Trigger phrases include "инфо-помощник по клиентам", "поводы касания на сегодня", "что нового у клиентов".
---

# Info-Helper Skill

## Overview

Каждое утро менеджеру нужны **3-5 конкретных поводов** позвонить конкретным клиентам. Скилл собирает их за 1-2 минуты на компанию через WebSearch + WebFetch и выдаёт Markdown-отчёт + опционально доставляет в Telegram.

Дизайн под три режима:
1. **Интерактивный:** пользователь говорит «дай инфо по клиентам», skill отрабатывает на текущей сессии.
2. **Headless / cron:** запуск через `claude` CLI или Cursor agent, конфиг клиентов лежит в `config/clients.yaml`, отчёт пишется в файл и шлётся в Telegram.
3. **CRM-driven:** список клиентов подтягивается из CRM через её API (CRM-нода в config).

## When to use

- Пользователь говорит «инфо-помощник по клиентам», «поводы касания», «что у клиентов нового за сегодня».
- Запуск headless по cron из `runner/run.sh`.
- Пользователь готовит звонок и просит проверить «что у них нового за 7 дней».

## Inputs

### Интерактивный режим
- Список компаний (название + сайт). 1-50 за один прогон.
- Опционально: контекст продаж (что мы продаём — для подбора углов касания).

### Headless / cron режим
- `config/clients.yaml` — список клиентов и опции
- `config/settings.yaml` — глобальные настройки (свежесть, формат отчёта, Telegram-доставка)
- `cache/sent-events.json` — кэш отправленных событий (дедупликация)

## Workflow

### Stage 1 — Подгрузка контекста

Если запуск headless: прочитай `config/clients.yaml` и `config/settings.yaml`.
Если интерактивный: возьми список компаний из реплики пользователя.

Прочитай `cache/sent-events.json` (если файл есть) — это hash-set уже отправленных событий за последние 14 дней. Любые события, чей хэш заголовка в кэше — drop.

### Stage 2 — Confirm company identities

Для каждой компании сделай WebSearch `"{company.name}" {company.website}` → подтверждение, что нашёл правильную (в KZ часто одно имя у нескольких юрлиц).

В headless-режиме при уверенности <70% **пропусти компанию** и залогируй в отчёт «нужно подтвердить».

### Stage 3 — Сбор сигналов по каждой компании

Для каждой выполни параллельно 4 WebSearch:
- `"{company.name}" новости 2026`
- `"{company.name}" CEO OR директор OR назначение 2026`
- `"{company.name}" пресс-релиз OR launch OR партнёрство 2026`
- `"{company.name}" hh.kz вакансии` (для KZ)

WebFetch топ-5 ссылок на каждую компанию. Извлеки: заголовок, дату публикации, ключевые факты (1-2 предложения), URL.

### Stage 4 — Фильтр и приоритизация

Для каждого факта проверь:
- **Свежесть:** дата ≤ {{settings.freshness_days, default: 7}}. Старше — drop (или отложи в секцию «контекст», если settings.show_context = true).
- **Конкретность:** содержит имена, цифры, цитаты, конкретный продукт. Generic-факты типа «компания работает на рынке» — drop.
- **Дедуп:** хэш заголовка не в `cache/sent-events.json`. Если есть — drop.
- **Actionability:** менеджер сможет сегодня использовать в звонке.

Из оставшихся выбери top-5 на компанию по важности.

### Stage 5 — Формулировка поводов

Для каждого факта сгенерируй:

**hook** — одна строка, конкретная, на русском.
- ❌ «Компания расширяется»
- ✅ «Открыли новый хаб в Шымкенте, площадь 3000 м²»

**date** — формат «{день} {месяц} ({N} дней назад)».

**source** — URL.

**opening_line** — готовая первая фраза менеджера:
- max 20 слов
- русский, деловой на «вы»
- ссылка на событие + открытый вопрос
- KZ-этикет: по имени или имени-отчеству (если знаешь), без панибратства
- без штампов («здравствуйте, я из...», «уважаемая компания...»)
- См. правила в репо [ai-camp-enrich-and-pitch](https://github.com/dkoraitest/ai-camp-enrich-and-pitch) — там в SKILL.md есть banned jargon list и KZ-warmup rules

### Stage 6 — Отчёт

Сгенерируй Markdown по шаблону:

```markdown
# ☕ Поводы касания на {today_ru}

> {N} поводов по {M} клиентам. Свежесть: ≤{freshness_days} дней. Дубли отфильтрованы.

---

## {company.name}

🎯 **{hook}**
📅 {date}
🔗 {source}
💬 «{opening_line}»

(3-5 повторов)

---

## {company.name 2}
...

---

## Контекст за {freshness_days}-30 дней (только для headless settings.show_context=true)

- {company}: {factor} ({date}, {url})
```

Если по компании нет свежих поводов — выведи:
```
## {company.name}
☕ Свежих поводов нет. Попробуй завтра.
```

### Stage 7 — Сохранение и доставка

1. **Сохрани отчёт:** `reports/info-helper-{YYYY-MM-DD}.md`.
2. **Обнови кэш:** добавь хэши новых events в `cache/sent-events.json`, удали записи старше 14 дней.
3. **Telegram доставка** (если в settings есть `telegram.bot_token` и `telegram.chat_id`):
   - Split отчёт на сообщения ≤ 4000 символов (Telegram limit).
   - POST на `https://api.telegram.org/bot{token}/sendMessage` с `parse_mode=Markdown`, `disable_web_page_preview=false`.
   - При 429 — спи 5 секунд, повтори.

### Stage 8 — Возврат пути и кода

Headless: выведи в stdout JSON `{"report_path": "...", "events_sent": N, "companies_processed": M, "errors": [...]}` и exit 0.
Интерактивный: покажи путь к отчёту и саммари в чате.

## Free vs Paid stack

| Источник | Free | Paid |
|----------|------|------|
| Web search | ✅ WebSearch (built-in) | — |
| Page content | ✅ WebFetch (built-in) | — |
| KZ company facts | ✅ adata.kz через WebFetch | goszakup API ($0, нужен token) |
| LinkedIn posts | ❌ | Apify `harvestapi/linkedin-profile-scraper` (~$0.10/profile, через `APIFY_API_KEY`) |
| Twitter/X | ❌ | xAI Grok через `x-research` skill (`XAI_API_KEY`) |
| HH.kz vacancies | ✅ WebFetch на vacancy URL | — |

Скилл работает out-of-the-box на free-стеке. Paid интеграции авто-определяются по env-переменным и добавляют точности.

## Что важно для cron-режима

1. **Запускай в headless** через `claude -p "/info-helper run from config"` (см. `runner/run.sh`).
2. **Без интерактивных вопросов:** при неуверенности → drop клиента и залогируй в отчёт.
3. **Idempotency:** повторный запуск в течение дня **не должен отправлять те же события** — для этого `cache/sent-events.json`.
4. **Graceful failure:** если одна компания упала — продолжай по остальным.
5. **Логи:** `logs/run-{YYYY-MM-DD-HHmm}.log` — stdout + stderr.

## Конфигурация

См. `config/clients.yaml.example` и `config/settings.yaml.example`.

## Установка и cron

См. `runner/README.md` — там команды для cron / launchd / Make-вебхука.
