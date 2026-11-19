#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT=${SCRIPT:-$HERE/../home/base/.local/bin/omp-usage}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

ms() {
  local t=${1%%.*}
  t=${t%Z}Z
  echo $(($(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$t" +%s 2>/dev/null || date -u -d "$t" +%s) * 1000))
}

export OMP_HOME="$TMP/omp" CODEX_HOME="$TMP/codex"
SESSION_ID=0000aaaa-0000-0000-0000-000000000001
DIR="$OMP_HOME/agent/sessions/-work"
PARENT="$DIR/2026-01-05T10-00-00-000Z_$SESSION_ID.jsonl"
mkdir -p "$DIR/2026-01-05T10-00-00-000Z_$SESSION_ID" "$CODEX_HOME"

assistant() { # timestamp duration_ms stop_reason total_tokens
  local end; end=$(ms "$1")
  printf '{"type":"message","timestamp":"%s","message":{"role":"assistant","provider":"openai-codex","model":"m","credentialId":1,"stopReason":"%s","timestamp":%s,"completedAt":%s,"duration":%s,"usage":{"input":%s,"output":0,"cacheRead":0,"totalTokens":%s,"cost":{"total":0.01}},"content":[]}}\n' \
    "$1" "$3" "$((end - $2))" "$end" "$2" "$4" "$4"
}

{
  printf '{"type":"title","title":"\xef\x84\xa0 Fixture task"}\n'
  printf '{"type":"session","id":"%s","timestamp":"2026-01-05T10:00:00.000Z","cwd":"/nonexistent/work"}\n' "$SESSION_ID"
  printf '{"type":"message","timestamp":"2026-01-05T10:01:00.000Z","message":{"role":"user","content":[]}}\n'
  assistant 2026-01-05T10:01:30.000Z 30000 toolUse 1000
  printf '{"type":"custom","customType":"tool_execution_start","timestamp":"2026-01-05T10:01:30.000Z","data":{"toolCallId":"t1","toolName":"eval","startedAt":"2026-01-05T10:01:30.000Z","intent":"Waiting for the review decision"}}\n'
  printf '{"type":"message","timestamp":"2026-01-05T10:11:30.000Z","message":{"role":"toolResult","toolCallId":"t1","content":[]}}\n'
  assistant 2026-01-05T10:12:00.000Z 30000 stop 1000
  printf '{"type":"message","timestamp":"2026-01-05T10:20:00.000Z","message":{"role":"user","content":[]}}\n'
  assistant 2026-01-05T10:21:00.000Z 60000 stop 2000
  printf '{"type":"custom","customType":"date-cwd-reminder","timestamp":"2026-01-05T10:30:00.000Z"}\n'
} >"$PARENT"

assistant 2026-01-05T10:06:00.000Z 120000 stop 500 >"$DIR/2026-01-05T10-00-00-000Z_$SESSION_ID/Helper.jsonl"

sqlite3 "$OMP_HOME/agent/agent.db" <<SQL
CREATE TABLE auth_credentials (id INTEGER PRIMARY KEY, provider TEXT, identity_key TEXT);
CREATE TABLE usage_history (recorded_at INTEGER, account_key TEXT, limit_id TEXT, window_label TEXT, used_fraction REAL, status TEXT, resets_at INTEGER);
CREATE TABLE cache (key TEXT PRIMARY KEY, value TEXT, expires_at INTEGER);
INSERT INTO auth_credentials VALUES (1, 'openai-codex', 'email:me@example.edu|org:org-1');
INSERT INTO usage_history VALUES
  ($(ms 2026-01-05T10:01:45Z), 'oauth|account:org-1|x', 'openai-codex:primary', '5 hours', 0.5, 'ok', $(ms 2026-01-05T14:00:00Z)),
  ($(ms 2026-01-05T10:15:00Z), 'oauth|account:org-1|x', 'openai-codex:primary', '5 hours', 1.0, 'warning', $(ms 2026-01-05T14:00:00Z)),
  ($(ms 2026-01-05T10:15:00Z), 'oauth|account:org-1|x', 'openai-codex:secondary', '7 days', 0.1, 'ok', $(ms 2026-01-10T00:00:00Z));
INSERT INTO cache VALUES ('usage_cache:report:1:openai-codex:x|org:org-1', '{"value":{"metadata":{"planType":"education"}}}', 0);
SQL

out=$("$SCRIPT" --since 2026-01-05T09:00:00Z --until 2026-01-05T11:00:00Z --json)
check() { # jq-filter expected description
  local got; got=$(jq -r "$1" <<<"$out")
  [[ $got == "$2" ]] || fail "$3: expected $2, got $got"
}

min=60000
check '.reports[0].timing.waitingForPromptMs' $((9 * min)) "prompt wait includes time before the first prompt and between turns"
check '.reports[0].timing.blockedOnOperatorMs' $((8 * min)) "operator wait excludes overlapping subagent work"
check '.reports[0].timing.activeMs' $((4 * min)) "active time"
check '.reports[0].timing.lastActivityAt' "$(ms 2026-01-05T10:21:00Z)" "trailing non-activity records are ignored"
check '.reports[0].totals.total' 4500 "tokens include subagents"
check '.reports[0].subagents | join(",")' Helper "subagent discovery"
check '.accounts[0].plan' education "plan type"
check '.accounts[0].overflows[0].estimatedFullAt' "$(ms 2026-01-05T10:12:00Z)" "crossover calibrated on the partial reading"
check '.accounts[0].overflows[0].after.confirmed.total' 2000 "usage after the first 100% reading"
check '.accounts[0].overflows[0].after.estimated.total' 2000 "usage after the estimated crossover"

md=$("$SCRIPT" --since 2026-01-05T09:00:00Z --until 2026-01-05T11:00:00Z)
grep -q '^### 2026-01-05: Fixture task$' <<<"$md" || fail "markdown heading strips the title icon"
grep -q '0h04m agent-active' <<<"$md" || fail "markdown active time"

printf 'ok\n'
