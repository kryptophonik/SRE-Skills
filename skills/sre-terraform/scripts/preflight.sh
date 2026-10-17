#!/usr/bin/env bash
# preflight.sh: read-only context check before any plan. Shows the Terraform version,
# workspace, backend type, and risky environment settings, without printing secrets.
#
# Usage: preflight.sh [-C DIR]
#
# Never prints backend config values, credentials, variable values, or env var values
# (only the names of risky variables). Does not run init, does not contact cloud APIs, and
# does not change anything. Exit: 0 = done (read the WARN lines), 1 = error.
#
# Docs: https://developer.hashicorp.com/terraform/cli/commands/version
#       https://developer.hashicorp.com/terraform/cli/commands/workspace/show
#       https://developer.hashicorp.com/terraform/language/backend
#       https://developer.hashicorp.com/terraform/cli/config/environment-variables
#       https://developer.hashicorp.com/terraform/language/files/dependency-lock
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -C) [[ $# -ge 2 ]] || die "-C needs a directory"; dir="$2"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
require_cmd terraform jq
init_tf "$dir"
root="${dir:-.}"
warns=0
w() { printf 'WARN: %s\n' "$*"; warns=$((warns+1)); }

echo "== Terraform"
ver_json="$("${TF[@]}" version -json 2>/dev/null)" || die "terraform version failed"
printf '%s' "$ver_json" | jq -r '"version:   \(.terraform_version)  (\(.platform))" + (if .terraform_outdated then "  [newer release available]" else "" end)'
printf '%s' "$ver_json" | jq -r '(.provider_selections // {}) | if length == 0 then "providers: (none selected; not initialized?)" else to_entries[] | "provider:  \(.key) \(.value)" end'

echo "== Workspace"
if [[ -n ${TF_WORKSPACE-} ]]; then echo "TF_WORKSPACE is set (it overrides the selected workspace)"; fi
ws="$("${TF[@]}" workspace show 2>/dev/null)" || ws="(unknown; run init first)"
echo "workspace: $ws"
[[ $ws == default ]] && echo "note:      'default' workspace. Confirm this is the environment you mean."

echo "== Backend (type only; config values are never printed)"
data_dir="${TF_DATA_DIR:-$root/.terraform}"
[[ -n ${TF_DATA_DIR-} && -n $dir && ${TF_DATA_DIR} != /* ]] && data_dir="$root/$TF_DATA_DIR"
if [[ -f $data_dir/terraform.tfstate ]]; then
  jq -r '"backend:   " + ((.backend.type // "none recorded") | tostring)' "$data_dir/terraform.tfstate"
else
  echo "backend:   local (default), or not initialized (no $data_dir/terraform.tfstate)"
fi

echo "== Files"
if [[ -f $root/.terraform.lock.hcl ]]; then echo "lock file: present"; else w "no .terraform.lock.hcl, so provider versions are not pinned (fine if only built-in providers). Commit the lock file."; fi
shopt -s nullglob
seen=$'\n'  # newline-delimited list (bash 3.2: no associative arrays)
for f in "$root"/*.tfstate "$root"/*.tfstate.* "$root"/tfplan "$root"/*.tfplan "$root"/tfplan.json; do
  [[ -e $f ]] || continue
  case $seen in *$'\n'"$f"$'\n'*) continue ;; esac
  seen+="$f"$'\n'
  w "sensitive file on disk: $(basename "$f") (state and plan files hold secrets in cleartext; never commit, upload, or paste them)"
  if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 && ! git -C "$root" check-ignore -q -- "$(basename "$f")"; then
    w "  ...and git does NOT ignore $(basename "$f"). Add it to .gitignore."
  fi
done
shopt -u nullglob

echo "== Environment (names only)"
while IFS='=' read -r name _; do
  case "$name" in
    TF_CLI_ARGS|TF_CLI_ARGS_*) w "$name is set; it adds flags to every matching terraform command (check for -auto-approve, -lock=false, -target)" ;;
    TF_LOG|TF_LOG_CORE|TF_LOG_PROVIDER) w "$name is set; debug logs can contain sensitive values. Do not share them." ;;
    TF_LOG_PATH) w "TF_LOG_PATH is set; a log file is being written (may contain secrets)" ;;
  esac
done < <(env | sort)
nvars="$(env | grep -c '^TF_VAR_' || true)"
[[ $nvars -gt 0 ]] && echo "TF_VAR_*:  $nvars variable(s) set (values not shown)"
ntok="$(env | grep -c '^TF_TOKEN_' || true)"
[[ $ntok -gt 0 ]] && echo "TF_TOKEN_*: $ntok registry/HCP token(s) present (values not shown)"

echo "== Next"
echo "Confirm the cloud account, subscription, or project matches this workspace with your provider's identity command (for example, the CLI's 'who am I' call) before you plan."
echo "Preflight done with $warns warning(s)."
