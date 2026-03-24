#!/usr/bin/env bash
set -euo pipefail

TARGETS_FILE="${1:-targets.txt}"
WARN_DAYS="${WARN_DAYS:-30}"
CRIT_DAYS="${CRIT_DAYS:-7}"
TIMEOUT="${TIMEOUT:-8}"

# Skapa Job Summary-output
SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-/dev/null}"

now_epoch="$(date +%s)"

ok=0
warn=0
crit=0

# För "faila jobben bara på CRIT" sätter vi exitkod på slutet.
exit_code=0

get_enddate() {
  local host="$1"
  local port="$2"

  # SNI med -servername + timeout
  timeout "${TIMEOUT}" openssl s_client \
    -servername "$host" \
    -connect "${host}:${port}" </dev/null 2>/dev/null \
  | openssl x509 -noout -enddate 2>/dev/null \
  | sed 's/^notAfter=//'
}

echo "## SSL Certificate Expiry Report" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"
echo "| Host | Status | Days left | Expires |" >> "$SUMMARY_FILE"
echo "|---|---:|---:|---|" >> "$SUMMARY_FILE"

while IFS= read -r line; do
  line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "$line" || "$line" =~ ^# ]] && continue

  host="$line"
  port="443"

  if [[ "$line" == *:* ]]; then
    host="${line%:*}"
    port="${line##*:}"
  fi

  enddate="$(get_enddate "$host" "$port" || true)"
  if [[ -z "$enddate" ]]; then
    echo "::error::$host:$port – kunde inte läsa certifikat (timeout/DNS/handshake?)"
    echo "| $host:$port | ❌ CRIT | - | - |" >> "$SUMMARY_FILE"
    ((crit++))
    exit_code=2
    continue
  fi

  exp_epoch="$(date -d "$enddate" +%s 2>/dev/null || true)"
  if [[ -z "$exp_epoch" ]]; then
    echo "::error::$host:$port – kunde inte tolka datum: $enddate"
    echo "| $host:$port | ❌ CRIT | - | $enddate |" >> "$SUMMARY_FILE"
    ((crit++))
    exit_code=2
    continue
  fi

  days_left=$(( (exp_epoch - now_epoch) / 86400 ))

  if (( days_left <= CRIT_DAYS )); then
    echo "::error::$host:$port – cert går ut om ${days_left} dagar ($enddate)"
    echo "| $host:$port | ❌ CRIT | $days_left | $enddate |" >> "$SUMMARY_FILE"
    ((crit++))
    exit_code=2
  elif (( days_left <= WARN_DAYS )); then
    echo "::warning::$host:$port – cert går ut om ${days_left} dagar ($enddate)"
    echo "| $host:$port | ⚠️ WARN | $days_left | $enddate |" >> "$SUMMARY_FILE"
    ((warn++))
    # exit_code lämnas som 0 om du inte vill faila på WARN
  else
    echo "$host:$port – OK ($days_left dagar kvar) exp: $enddate"
    echo "| $host:$port | ✅ OK | $days_left | $enddate |" >> "$SUMMARY_FILE"
    ((ok++))
  fi
done < "$TARGETS_FILE"

echo "" >> "$SUMMARY_FILE"
echo "**Totals:** ✅ OK: $ok · ⚠️ WARN: $warn · ❌ CRIT: $crit" >> "$SUMMARY_FILE"

# Exportera totals som outputs via env (kan användas för notifieringar)
{
  echo "SSL_OK=$ok"
  echo "SSL_WARN=$warn"
  echo "SSL_CRIT=$crit"
} >> "${GITHUB_ENV}"

exit "$exit_code"
