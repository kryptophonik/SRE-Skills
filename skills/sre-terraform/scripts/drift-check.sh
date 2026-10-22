#!/usr/bin/env bash
# drift-check.sh: read-only drift check with
# `terraform plan -refresh-only -detailed-exitcode`.
#
# Usage:
#   drift-check.sh [-C DIR] [--show-log] [-- <allowed plan options>]
#
#   Allowed plan options: -var-file=FILE, -var=NAME=VALUE (put secrets in -var-file or TF_VAR_*;
#   -var values can appear in process listings), -lock-timeout=DURATION, -parallelism=N,
#   -compact-warnings. Anything else is refused (for example -lock=false, -target, -replace,
#   -destroy, -refresh=false, -auto-approve).
#   --show-log  also print Terraform's human-readable plan output (masks values marked
#               sensitive, but provider attributes not marked sensitive are shown as is)
#
# Exit codes (same as -detailed-exitcode):
#   0 = no drift (state matches the real objects and root outputs)
#   1 = error
#   2 = drift detected (see the list; nothing was changed). It then lists the options:
#       (a) change config, (b) revert reality, (c) accept into state. (c) is not offered when
#       a drifted object no longer exists, because accepting would drop it from state.
#
# Writes nothing: it never applies, never runs `terraform refresh`, and never runs
# `apply -refresh-only` (both write state). It keeps the normal state lock. The plan is
# saved only to a private temp dir so it can be summarized by address, then deleted.
#
# Docs: https://developer.hashicorp.com/terraform/cli/commands/plan#planning-modes
#       https://developer.hashicorp.com/terraform/cli/commands/plan#other-options   (-detailed-exitcode)
#       https://developer.hashicorp.com/terraform/cli/commands/refresh             (deprecated; = apply -refresh-only -auto-approve)
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"

dir="" show_log=false extra=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -C) [[ $# -ge 2 ]] || die "-C needs a directory"; dir="$2"; shift 2 ;;
    --show-log) show_log=true; shift ;;
    -h|--help) sed -n '2,27p' "$0"; exit 0 ;;
    --) shift; extra=("$@"); break ;;
    *) die "unknown argument: $1 (pass plan options after --)" ;;
  esac
done

for a in ${extra[@]+"${extra[@]}"}; do
  case "$a" in
    -var-file=*|-lock-timeout=*|-parallelism=*|-compact-warnings) ;;
    -var=*) warn "-var values can be seen in process listings; use -var-file or TF_VAR_* for secrets." ;;
    *) die "refused plan option '$a'. drift-check only allows -var-file, -var, -lock-timeout, -parallelism, -compact-warnings." ;;
  esac
done

require_cmd terraform jq
guard_tf_cli_args
init_tf "$dir"
make_private_tmp

planfile="$TMPD/drift.tfplan"
set +e
"${TF[@]}" plan -refresh-only -detailed-exitcode -input=false -no-color \
  -out="$planfile" ${extra[@]+"${extra[@]}"} >"$TMPD/plan.log" 2>&1
rc=$?
set -e

case "$rc" in
  0)
    info "NO DRIFT (exit 0): Terraform state matches the real objects and root outputs."
    $show_log && cat "$TMPD/plan.log"
    exit 0 ;;
  2)
    info "DRIFT DETECTED (exit 2): objects changed outside Terraform. Nothing was changed."
    pr_args=(--drift-only); [[ -n $dir ]] && pr_args=(-C "$dir" --drift-only)
    "$here/plan-risk.sh" ${pr_args[@]+"${pr_args[@]}"} "$planfile" || true
    $show_log && { echo "--- terraform output ---"; cat "$TMPD/plan.log"; }
    # Objects that no longer exist show as "delete" drift. Accepting that into state drops them.
    gone="$("${TF[@]}" show -json -no-color "$planfile" 2>/dev/null \
      | jq -r '(.resource_drift // [])[] | select(.change.actions == ["delete"]) | .address' 2>/dev/null)" || gone=""
    info ""
    info "Next: find out why it drifted (incident fix, console change, another tool). Then propose one of:"
    info "  (a) change the config to match reality, then run a normal plan review;"
    info "  (b) revert reality: run a normal plan review and apply the approved saved plan, which puts"
    info "      the real objects back to what the config says;"
    if [[ -n $gone ]]; then
      info "  (c) NOT OFFERED: these drifted objects no longer exist, and accepting the drift into state"
      info "      (apply -refresh-only) would remove them from state, so Terraform stops tracking them:"
      while IFS= read -r g; do info "        - $g"; done <<<"$gone"
      info "      Use (b) to recreate them, or (a) to remove them from the config on purpose."
    else
      info "  (c) accept reality into state: a human approves 'terraform plan -refresh-only -out=tfplan',"
      info "      reviewed like any plan, then 'terraform apply tfplan' (writes state)."
    fi
    info "Never run 'terraform refresh' or 'apply -refresh-only -auto-approve'."
    exit 2 ;;
  *)
    info "ERROR (exit $rc): terraform plan -refresh-only failed. Diagnostics:"
    # Print only the diagnostic blocks, not the whole plan body.
    grep -E '^(│|╷|╵|Error:|Warning:)' "$TMPD/plan.log" || tail -n 20 "$TMPD/plan.log"
    exit 1 ;;
esac
