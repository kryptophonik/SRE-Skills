#!/usr/bin/env bash
# Shared helpers for the read-only Terraform scripts. Source it; do not execute it.
# Docs: https://developer.hashicorp.com/terraform/cli/commands
#       https://developer.hashicorp.com/terraform/cli/config/environment-variables

# Flags that change what a plan/apply does, or turn off safety features.
# Read-only scripts never pass these, and refuse to run if TF_CLI_ARGS* inject them.
TF_DANGEROUS_FLAGS_RE='(^|[[:space:]])-(auto-approve|lock=false|replace(=|[[:space:]])|target(=|[[:space:]])|destroy|refresh=false|force|migrate-state|force-copy|reconfigure|upgrade|state-out|backup|generate-config-out)'

die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
info() { printf '%s\n' "$*"; }

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "'$c' is required but not on PATH"
  done
}

# TF_CLI_ARGS and TF_CLI_ARGS_<command> are added to every matching terraform call.
# They could quietly add -auto-approve, -lock=false, -target, etc.
# https://developer.hashicorp.com/terraform/cli/config/environment-variables#tf_cli_args-and-tf_cli_args_name
guard_tf_cli_args() {
  local name val
  while IFS='=' read -r name _; do
    [[ $name == TF_CLI_ARGS || $name == TF_CLI_ARGS_* ]] || continue
    val="${!name-}"
    if [[ " $val" =~ $TF_DANGEROUS_FLAGS_RE ]]; then
      die "$name injects a flag that read-only helpers refuse. Unset it and try again (value not shown)."
    fi
    warn "$name is set and will be added to terraform commands (value not shown)."
  done < <(env)
}

# Build the base terraform command (with optional -chdir). Sets the TF array.
init_tf() {
  local dir="${1:-}"
  TF=(terraform)
  if [[ -n $dir ]]; then
    [[ -d $dir ]] || die "directory not found: $dir"
    TF+=("-chdir=$dir")
  fi
  export TF_IN_AUTOMATION=1   # shorter output, no "run terraform apply" hints
  export TF_INPUT=0           # never prompt
}

# Private temp dir (mode 700), removed on exit. Saved plans hold secrets in cleartext:
# https://developer.hashicorp.com/terraform/cli/commands/plan#out-filename
make_private_tmp() {
  umask 077
  TMPD="$(mktemp -d "${TMPDIR:-/tmp}/tf-ro.XXXXXX")"
  trap 'rm -rf -- "$TMPD"' EXIT
}
