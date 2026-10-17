#!/usr/bin/env bash
# tf-readonly.sh: allowlist wrapper. It runs only read-only Terraform commands and refuses
# everything else, including apply and destroy. Point Claude Code (or a human) at this
# script instead of bare `terraform` during investigation.
#
# Usage: tf-readonly.sh [-C DIR] <subcommand> [args...]
#
# Allowed:
#   version | validate | providers (no subcommand) | workspace show | workspace list
#   fmt              forced to -check (never rewrites files)
#   init             forced to -input=false -lockfile=readonly; refuses -upgrade,
#                    -migrate-state, -reconfigure, -force-copy, -from-module
#   plan             forced to -input=false; refuses -destroy, -replace, -target,
#                    -lock=false, -refresh=false, -generate-config-out
#   show [-no-color] [PLANFILE]  human output only (masks values marked sensitive);
#                    `show -json` is refused, so use plan-risk.sh
#   state list [ADDR...]
#   state show ADDR  allowed with a warning: attributes not marked sensitive are printed
#                    as is (a known leak path)
# Refused, with the reason printed: apply, destroy, import, taint, untaint, refresh,
#   force-unlock, state mv/rm/push/pull/replace-provider, workspace new/select/delete,
#   output, console, login, logout, get, test, and anything else.
#
# Exit: the terraform exit code, or 1 if refused (plan's -detailed-exitcode works as usual).
# Docs: https://developer.hashicorp.com/terraform/cli/commands
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

dir=""
if [[ ${1-} == "-C" ]]; then [[ $# -ge 2 ]] || die "-C needs a directory"; dir="$2"; shift 2; fi
[[ $# -ge 1 ]] || die "usage: tf-readonly.sh [-C DIR] <subcommand> [args...]"
sub="$1"; shift

refuse() { die "refused: terraform $sub $* is not read-only. $REASON See references/dangerous-commands.md. A human must approve and run it."; }

has_flag() { # has_flag <regex> args...
  local re="$1"; shift; local a
  for a in "$@"; do [[ $a =~ $re ]] && return 0; done; return 1
}

require_cmd terraform
guard_tf_cli_args
init_tf "$dir"

case "$sub" in
  version|validate)
    exec "${TF[@]}" "$sub" "$@" ;;
  providers)
    [[ $# -eq 0 || ${1-} == -* ]] || { REASON="'providers $1' writes files (lock or mirror)."; refuse "$@"; }
    exec "${TF[@]}" providers "$@" ;;
  workspace)
    case "${1-}" in
      show|list) exec "${TF[@]}" workspace "$@" ;;
      *) REASON="Changing, creating, or deleting workspaces changes which state is targeted."; refuse "$@" ;;
    esac ;;
  fmt)
    has_flag '^-write(=true)?$' "$@" && { REASON="fmt may only check."; refuse "$@"; }
    exec "${TF[@]}" fmt -check "$@" ;;
  init)
    has_flag '^-(upgrade|migrate-state|reconfigure|force-copy|from-module|lock=false)' "$@" \
      && { REASON="These init options change provider versions, backend config, or state location."; refuse "$@"; }
    exec "${TF[@]}" init -input=false -lockfile=readonly "$@" ;;
  plan)
    has_flag '^-(destroy|replace|target|lock=false|refresh=false|generate-config-out)' "$@" \
      && { REASON="Destroy, replace, or target plans and lock/refresh bypasses need human approval."; refuse "$@"; }
    exec "${TF[@]}" plan -input=false "$@" ;;
  show)
    has_flag '^-json$' "$@" && { REASON="show -json prints sensitive values in plain text (https://developer.hashicorp.com/terraform/cli/commands/show). Use scripts/plan-risk.sh."; refuse "$@"; }
    exec "${TF[@]}" show "$@" ;;
  state)
    case "${1-}" in
      list) exec "${TF[@]}" state "$@" ;;
      show)
        warn "state show prints every attribute that is not marked sensitive. Do not paste the output anywhere public."
        exec "${TF[@]}" state "$@" ;;
      pull) REASON="state pull prints the whole state, including secrets."; refuse "$@" ;;
      *) REASON="State surgery (mv/rm/push/replace-provider) changes state directly."; refuse "$@" ;;
    esac ;;
  apply|destroy)
    REASON="This helper never runs $sub. Apply only a reviewed saved plan (terraform apply <planfile>) after explicit human approval."; refuse "$@" ;;
  refresh)
    REASON="terraform refresh = apply -refresh-only -auto-approve and writes state. Use scripts/drift-check.sh."; refuse "$@" ;;
  output|console)
    REASON="$sub can print sensitive values."; refuse "$@" ;;
  *)
    REASON="'$sub' is not on the read-only allowlist."; refuse "$@" ;;
esac
