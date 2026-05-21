#!/usr/bin/env bash
# ai-camp-info-helper/runner/run.sh
#
# Headless-запуск скилла info-helper через Claude CLI или Cursor CLI.
# Скрипт спроектирован для запуска по cron в 9:00 каждый день.
#
# Зависимости:
#   - Claude CLI (claude.ai/claude-code) ИЛИ Cursor CLI (cursor)
#   - Подгруженный API ключ Anthropic (ANTHROPIC_API_KEY)
#   - Опционально: APIFY_API_KEY, XAI_API_KEY для расширенных источников
#   - Опционально: TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID для доставки
#
# Использование:
#   ./run.sh                     # дефолтный режим — читает config/clients.yaml
#   ./run.sh --dry-run           # сухой прогон без сохранения и отправки
#   ./run.sh --once              # одноразовый прогон (без cron-логики)
#   ./run.sh --client "АкмеЛогистикс"  # прогон только по одному клиенту
#
# Логи: ./logs/run-YYYY-MM-DD-HHmm.log

set -euo pipefail

# --- Setup ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

cd "$REPO_DIR"

# Подгружаем .env, если есть
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

# Проверки
if [ ! -f config/clients.yaml ]; then
  echo "[ERROR] config/clients.yaml не найден. Скопируй из clients.yaml.example и заполни." >&2
  exit 2
fi

if [ ! -f config/settings.yaml ]; then
  echo "[ERROR] config/settings.yaml не найден. Скопируй из settings.yaml.example и заполни." >&2
  exit 2
fi

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "[ERROR] ANTHROPIC_API_KEY не установлен. Положи в .env или экспортни в shell." >&2
  exit 2
fi

mkdir -p logs reports cache

TIMESTAMP="$(date +%Y-%m-%d-%H%M)"
LOG_FILE="logs/run-${TIMESTAMP}.log"
REPORT_DATE="$(date +%Y-%m-%d)"
REPORT_FILE="reports/info-helper-${REPORT_DATE}.md"

# --- Parse args ---

MODE="cron"
SPECIFIC_CLIENT=""
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --once)
      MODE="once"
      shift
      ;;
    --client)
      SPECIFIC_CLIENT="$2"
      shift 2
      ;;
    *)
      echo "[WARN] Неизвестный флаг: $1" >&2
      shift
      ;;
  esac
done

# --- Build the prompt ---

INSTRUCTION=$(cat <<'EOF'
Activate the info-helper skill and run in headless cron mode:

1. Read config/clients.yaml (list of clients + sales_context).
2. Read config/settings.yaml (freshness, language, delivery options).
3. Read cache/sent-events.json (if exists) for deduplication.
4. For each client, gather fresh signals (≤ freshness_days), filter via the skill's rules, generate touch reasons with hooks and opening lines.
5. Save the Markdown report to reports/info-helper-{TODAY}.md.
6. Update cache/sent-events.json with the new event hashes; expire entries older than dedup.ttl_days.
7. If settings.delivery.telegram.enabled = true, send the report to Telegram (split by chunk_size_chars).
8. At the end, output a JSON line to stdout:
   {"report_path": "...", "events_sent": N, "companies_processed": M, "errors": [...]}

Do NOT ask the user any clarifying questions. If a company can't be verified with ≥70% confidence, skip it and log "skipped" in the errors array.

EOF
)

if [ -n "$SPECIFIC_CLIENT" ]; then
  INSTRUCTION="${INSTRUCTION}

Filter: process ONLY the client named '${SPECIFIC_CLIENT}'."
fi

if [ "$DRY_RUN" = "true" ]; then
  INSTRUCTION="${INSTRUCTION}

DRY RUN: Do NOT save the report file, do NOT update cache, do NOT send to Telegram. Just generate the report content and output it to stdout."
fi

# --- Pick the CLI ---

CLI=""
if command -v claude >/dev/null 2>&1; then
  CLI="claude"
elif command -v cursor-agent >/dev/null 2>&1; then
  CLI="cursor-agent"
elif command -v cursor >/dev/null 2>&1; then
  CLI="cursor"
else
  echo "[ERROR] Не найден claude или cursor CLI. Установи Claude Code: https://claude.ai/claude-code" >&2
  exit 3
fi

echo "[INFO] Используем CLI: $CLI" | tee -a "$LOG_FILE"
echo "[INFO] Режим: $MODE, dry-run: $DRY_RUN" | tee -a "$LOG_FILE"
echo "[INFO] Лог: $LOG_FILE" | tee -a "$LOG_FILE"
echo "[INFO] Отчёт: $REPORT_FILE" | tee -a "$LOG_FILE"

# --- Run ---

case "$CLI" in
  claude)
    # Claude Code CLI: headless mode with -p flag
    # --dangerously-skip-permissions для cron (без интерактивных подтверждений)
    "$CLI" -p "$INSTRUCTION" \
      --dangerously-skip-permissions \
      --model claude-sonnet-4-6 \
      2>&1 | tee -a "$LOG_FILE"
    ;;
  cursor-agent|cursor)
    # Cursor agent CLI
    "$CLI" -p "$INSTRUCTION" 2>&1 | tee -a "$LOG_FILE"
    ;;
esac

EXIT_CODE=${PIPESTATUS[0]}

if [ $EXIT_CODE -eq 0 ]; then
  echo "[INFO] Прогон завершён успешно." | tee -a "$LOG_FILE"
else
  echo "[ERROR] Прогон завершился с кодом $EXIT_CODE." | tee -a "$LOG_FILE"
fi

# --- Опционально: дополнительная Telegram-доставка через shell (если CLI не справился) ---
# Если skill не отправил в Telegram, fallback на shell-доставку через delivery/telegram.sh
if [ "$DRY_RUN" = "false" ] && [ -f "$REPORT_FILE" ] && [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
  echo "[INFO] Fallback Telegram delivery..." | tee -a "$LOG_FILE"
  bash delivery/telegram.sh "$REPORT_FILE" 2>&1 | tee -a "$LOG_FILE" || true
fi

exit $EXIT_CODE
