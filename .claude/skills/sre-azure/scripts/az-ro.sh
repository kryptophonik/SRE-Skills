#!/usr/bin/env bash
# az-ro.sh: read-only guard around the Azure CLI.
# Usage: az-ro.sh --subscription <sub-id> <az args...>
# Only these final verbs are allowed: show, list, query, get-instance-view.
# `az rest` is allowed with --method get only, and its URL must name the same subscription.
# --subscription is appended to every call. Checked with `az <cmd> --help` (CLI 2.91.0):
# both `az rest` and `az monitor log-analytics query` list --subscription.
# log-analytics query is still scoped by the workspace GUID (-w); it comes from the
# preview `log-analytics` extension, which the CLI installs on first use.
# Sources:
#   https://learn.microsoft.com/cli/azure/reference-index
#   https://learn.microsoft.com/cli/azure/use-azure-cli-successfully#subscriptions
#   https://learn.microsoft.com/cli/azure/reference-index#az-rest
#   https://learn.microsoft.com/cli/azure/monitor/log-analytics#az-monitor-log-analytics-query
set -euo pipefail

usage() { echo "usage: $0 --subscription <sub-id> <az group...> <show|list|query|get-instance-view> [flags]" >&2; exit 2; }

SUB=""
if [[ "${1:-}" == "--subscription" && -n "${2:-}" ]]; then SUB="$2"; shift 2; else usage; fi
[[ $# -ge 1 ]] || usage

# Refuse anything that tries to override the subscription or escalate.
for a in "$@"; do
  case "$a" in
    --subscription|--subscription=*) echo "refused: pass --subscription only once, first" >&2; exit 3 ;;
    --admin|--yes|-y|--no-wait|--force*) echo "refused: flag '$a' not allowed in read-only mode" >&2; exit 3 ;;
  esac
done

# Find the verb: the last positional token before the first flag.
verb=""; positional=()
for a in "$@"; do [[ "$a" == -* ]] && break; positional+=("$a"); verb="$a"; done

if [[ "${positional[0]:-}" == "rest" ]]; then
  method=""
  args=("$@")
  for i in "${!args[@]}"; do
    case "${args[$i]}" in
      --method|-m) method="${args[$((i+1))]:-}" ;;
      --method=*) method="${args[$i]#--method=}" ;;
    esac
  done
  [[ "${method,,}" == "get" ]] || { echo "refused: az rest needs an explicit --method get" >&2; exit 3; }
  # The subscription in the URL must match the one passed with --subscription.
  url=""
  for i in "${!args[@]}"; do
    case "${args[$i]}" in --url|--uri|-u) url="${args[$((i+1))]:-}" ;; --url=*|--uri=*) url="${args[$i]#*=}" ;; esac
  done
  [[ "$url" == *"/subscriptions/${SUB}/"* ]] || { echo "refused: az rest URL must contain /subscriptions/${SUB}/" >&2; exit 3; }
  exec az "$@" --subscription "$SUB"
else
  case "$verb" in
    show|list|query|get-instance-view) ;;
    *) echo "refused: verb '$verb' is not in the read-only allowlist (show|list|query|get-instance-view)" >&2; exit 3 ;;
  esac
  # Secret- or credential-returning subcommands are POST actions even when they read.
  for p in "${positional[@]}"; do
    case "$p" in
      keys|credential|credentials|secret|secrets|connection-string|list-keys|list-secrets|get-credentials)
        echo "refused: '$p' returns secrets or credentials" >&2; exit 3 ;;
    esac
  done
fi

exec az "$@" --subscription "$SUB"
