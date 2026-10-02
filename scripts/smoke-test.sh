#!/usr/bin/env bash
set -euo pipefail
APP_IP="$(terraform -chdir=terraform output -raw app_public_ip)"

echo "== Allowed request =="
curl -fsS -o /dev/null -w "HTTP %{http_code}\n" "http://$APP_IP:8080/"

echo "== Deterministic WAF block =="
code="$(curl -sS -o /dev/null -w '%{http_code}' "http://$APP_IP:8080/?q=FYND_WAF_BLOCK")"
test "$code" = "403" || { echo "Expected 403, got $code"; exit 1; }

echo "WAF smoke tests passed."
