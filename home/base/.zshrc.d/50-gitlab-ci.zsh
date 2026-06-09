_glab_ci_notify_success() {
  local repo="$1"
  local message="$2"

  if command -v osascript >/dev/null 2>&1; then
    osascript \
      -e 'on run argv' \
      -e 'display notification (item 2 of argv) with title "GitLab CI" subtitle (item 1 of argv) sound name "default"' \
      -e 'end run' \
      "$repo" "$message"
  else
    print -u2 "$repo: $message"
  fi
}

_glab_ci_notify_failure() {
  local repo="$1"
  local message="$2"
  local pipeline_url="${3:-}"

  if command -v osascript >/dev/null 2>&1; then
    osascript \
      -e 'on run argv' \
      -e 'set body to (item 1 of argv) & ": " & (item 2 of argv)' \
      -e 'if (count of argv) > 2 and (item 3 of argv) is not "" then set body to body & return & return & (item 3 of argv)' \
      -e 'display dialog body with title "GitLab CI" buttons {"OK"} default button "OK" with icon caution' \
      -e 'end run' \
      "$repo" "$message" "$pipeline_url"
  else
    print -u2 "$repo: $message"
    if [ -n "$pipeline_url" ]; then
      print -u2 "$pipeline_url"
    fi
  fi
}

glab-watch-notify() {
  local interval="${GLAB_WATCH_INTERVAL:-30}"
  local repo="${PWD:t}"
  local pipeline_status
  local pipeline_url
  local message

  while true; do
    pipeline_status="$(glab ci get --output json --jq '.status' "$@")"
    local code=$?
    if (( code != 0 )); then
      _glab_ci_notify_failure "$repo" "Could not read pipeline status"
      return "$code"
    fi

    pipeline_status="${pipeline_status//$'\n'/}"
    print -r -- "GitLab CI pipeline status: $pipeline_status"

    case "$pipeline_status" in
      success|failed|canceled|skipped|manual)
        break
        ;;
    esac

    sleep "$interval"
  done

  pipeline_url="$(glab ci get --output json --jq '.web_url // ""' "$@" 2>/dev/null || true)"
  pipeline_url="${pipeline_url//$'\n'/}"

  case "$pipeline_status" in
    success) message="Pipeline finished successfully" ;;
    failed) message="Pipeline failed" ;;
    canceled) message="Pipeline was canceled" ;;
    skipped) message="Pipeline was skipped" ;;
    manual) message="Pipeline is waiting on manual action" ;;
    *) message="Pipeline ended with status: $pipeline_status" ;;
  esac

  if [[ "$pipeline_status" == "success" ]]; then
    _glab_ci_notify_success "$repo" "$message"
  else
    _glab_ci_notify_failure "$repo" "$message" "$pipeline_url"
  fi

  [[ "$pipeline_status" == "success" ]]
}
