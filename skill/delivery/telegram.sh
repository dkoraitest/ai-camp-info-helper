#!/usr/bin/env bash
# delivery/telegram.sh — отправка готового Markdown-отчёта в Telegram.
#
# Вызывается из run.sh как fallback (если skill сам не отправил), либо вручную.
#
# Использование:
#   ./telegram.sh path/to/report.md
#
# Env:
#   TELEGRAM_BOT_TOKEN — обязательно
#   TELEGRAM_CHAT_ID — обязательно (число; для группы — отрицательное)
#   TELEGRAM_CHUNK_SIZE — опционально, дефолт 3800 (Telegram limit 4096)

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <path-to-markdown-report>" >&2
  exit 1
fi

REPORT="$1"

if [ ! -f "$REPORT" ]; then
  echo "[ERROR] Файл $REPORT не найден" >&2
  exit 2
fi

if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
  echo "[ERROR] Не заданы TELEGRAM_BOT_TOKEN и TELEGRAM_CHAT_ID в env" >&2
  exit 3
fi

CHUNK_SIZE="${TELEGRAM_CHUNK_SIZE:-3800}"
API="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"

# Читаем отчёт и режем на чанки по границе компании (---)
# Простая нарезка по символам: чтобы не порвать markdown посреди слова.
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

awk -v size="$CHUNK_SIZE" -v dir="$TMP_DIR" '
{
  buf = buf $0 "\n"
  if (length(buf) > size) {
    n++
    printf "%s", buf > (dir "/chunk-" sprintf("%03d", n) ".md")
    buf = ""
  }
}
END {
  if (length(buf) > 0) {
    n++
    printf "%s", buf > (dir "/chunk-" sprintf("%03d", n) ".md")
  }
}
' "$REPORT"

TOTAL=$(ls -1 "$TMP_DIR"/chunk-*.md 2>/dev/null | wc -l | tr -d ' ')

if [ "$TOTAL" -eq 0 ]; then
  echo "[WARN] Отчёт пустой, ничего не отправляем" >&2
  exit 0
fi

echo "[INFO] Отправляем $TOTAL чанков в Telegram chat $TELEGRAM_CHAT_ID"

for f in "$TMP_DIR"/chunk-*.md; do
  TEXT="$(cat "$f")"

  # Простая обработка повторов 429: retry до 3 раз
  for attempt in 1 2 3; do
    HTTP_CODE=$(curl -sS -o /tmp/tg-resp.json -w "%{http_code}" \
      -X POST "$API" \
      -d "chat_id=${TELEGRAM_CHAT_ID}" \
      --data-urlencode "text=${TEXT}" \
      -d "parse_mode=Markdown" \
      -d "disable_web_page_preview=false")

    if [ "$HTTP_CODE" = "200" ]; then
      break
    elif [ "$HTTP_CODE" = "429" ]; then
      RETRY=$(cat /tmp/tg-resp.json | grep -o '"retry_after":[0-9]*' | grep -o '[0-9]*' || echo "5")
      echo "[WARN] 429 Too Many Requests, спим $RETRY сек, попытка $attempt/3" >&2
      sleep "$RETRY"
    else
      echo "[ERROR] HTTP $HTTP_CODE, попытка $attempt/3" >&2
      cat /tmp/tg-resp.json >&2
      sleep 2
    fi
  done

  if [ "$HTTP_CODE" != "200" ]; then
    echo "[ERROR] Не удалось отправить чанк $(basename "$f") после 3 попыток" >&2
    exit 4
  fi

  # Пауза между чанками — чтобы не словить flood
  sleep 1
done

echo "[INFO] Все чанки отправлены."
