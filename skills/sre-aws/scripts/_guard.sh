#!/usr/bin/env bash
# Shared guard: refuse mutating AWS CLI verbs. Source this file; do not execute.
# Ref (2026-10-16): https://docs.aws.amazon.com/service-authorization/latest/reference/reference_policies_actions-resources-contextkeys.html
aws_ro() {
  local op="${2:-}"
  case "$op" in
    describe-*|list-*|get-*|lookup-*|tail|filter-log-events|start-query|stop-query) ;;
    *) echo "REFUSED: '$1 $op' is not on the read-only allowlist" >&2; return 2 ;;
  esac
  local args=()
  [[ -n "${AWS_PROFILE:-}" ]] && args+=(--profile "$AWS_PROFILE")
  aws ${args[@]+"${args[@]}"} "$@"
}
