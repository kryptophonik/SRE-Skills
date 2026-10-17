#!/usr/bin/env bash
# terraform-guard.sh: Claude Code PreToolUse hook for the Bash tool. A second safety layer
# under the skills' approval rules. It reads the hook JSON on stdin and returns:
#   deny  for commands that must never run from the agent: -auto-approve, destroy,
#         apply -destroy, apply without a saved plan file, refresh, force-unlock -force
#   ask   for commands that need a human's explicit approval in the permission prompt:
#         apply <planfile>, import, taint/untaint, force-unlock, state mv/rm/push/pull/
#         replace-provider, workspace new/select/delete, init -upgrade/-migrate-state/
#         -reconfigure/-force-copy, any -lock=false/-replace/-target/-destroy/-refresh=false,
#         and secret-exposing reads (show -json, state show, output, console), login/logout,
#         and TF_CLI_ARGS overrides
#   nothing (exit 0, no output) otherwise, so the normal permission flow applies.
#
# This is best-effort string matching, not a sandbox. Real controls are least-privilege
# credentials and approval in CI. It does not see terraform calls made inside scripts;
# the bundled scripts are read-only by design.
#
# Hook protocol: https://code.claude.com/docs/en/hooks  (PreToolUse, permissionDecision)
# Command docs:  https://developer.hashicorp.com/terraform/cli/commands
set -euo pipefail
command -v jq >/dev/null 2>&1 || { echo "terraform-guard: jq not found; cannot check command" >&2; exit 0; }

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
[[ -n $cmd ]] || exit 0
[[ $cmd == *terraform* || $cmd == *TF_CLI_ARGS* ]] || exit 0

decision="" reasons=()
bump() { # bump <deny|ask> <reason>
  if [[ $1 == deny ]]; then decision=deny
  elif [[ -z $decision ]]; then decision=ask; fi
  reasons+=("$2")
}

[[ $cmd == *TF_CLI_ARGS* ]] && bump ask "Command sets TF_CLI_ARGS*, which can add flags like -auto-approve or -lock=false to terraform."

# Split into simple commands on ; & | newline ` $( ( ) and check each one.
segments="$(printf '%s' "$cmd" | tr ';&|`()\n' '\n\n\n\n\n\n\n')"
while IFS= read -r seg; do
  read -ra t <<<"$seg" || true
  n=${#t[@]}
  i=0
  while [[ $i -lt $n && ${t[$i]##*/} != terraform ]]; do i=$((i+1)); done
  [[ $i -lt $n ]] || continue
  i=$((i+1))
  while [[ $i -lt $n && ${t[$i]} == -* ]]; do i=$((i+1)); done   # global opts, e.g. -chdir=DIR
  [[ $i -lt $n ]] || continue
  sub="${t[$i]}"; rest=("${t[@]:$((i+1))}")
  a1="${rest[0]-}"
  args=" ${rest[*]-} "

  [[ $args == *" -auto-approve"* ]] && bump deny "-auto-approve skips human review (https://developer.hashicorp.com/terraform/cli/commands/apply)."
  [[ $args =~ \ -lock=false ]]   && bump ask "-lock=false disables state locking ('dangerous if others might concurrently run commands')."
  [[ $args =~ \ -replace[=\ ] ]] && bump ask "-replace forces destroy and recreate of a resource."
  [[ $args =~ \ -target[=\ ] ]]  && bump ask "-target is for exceptional cases only and can hide drift."
  [[ $args =~ \ -refresh=false ]] && bump ask "-refresh=false ignores real-world changes; the plan may be wrong."

  case "$sub" in
    destroy) bump deny "terraform destroy deletes every managed object. A human runs it, not the agent." ;;
    refresh) bump deny "terraform refresh = apply -refresh-only -auto-approve (writes state). Use drift-check.sh." ;;
    apply)
      if [[ $args == *" -destroy"* ]]; then
        bump deny "apply -destroy deletes every managed object."
      else
        pos=0 varflags=0
        for a in ${rest[@]+"${rest[@]}"}; do
          [[ $a == -var* ]] && varflags=1
          [[ $a != -* ]] && pos=$((pos+1))
        done
        if [[ $pos -eq 1 && $varflags -eq 0 ]]; then
          bump ask "Applying a saved plan runs without a Terraform prompt. Approve only if a human reviewed this exact plan file (terraform show / plan-risk.sh)."
        else
          bump deny "apply without a saved, reviewed plan file. Run 'terraform plan -out=tfplan', review it, then apply tfplan with approval."
        fi
      fi ;;
    plan) [[ $args == *" -destroy"* ]] && bump ask "plan -destroy proposes deleting every managed object." ;;
    import|taint|untaint) bump ask "terraform $sub changes state; needs explicit human approval." ;;
    force-unlock)
      if [[ $args == *" -force"* ]]; then bump deny "force-unlock -force skips confirmation."
      else bump ask "force-unlock: confirm that no run is active (another apply could corrupt state)."; fi ;;
    state)
      case "$a1" in
        list) ;;
        show) bump ask "state show prints attributes not marked sensitive as plain text (secrets exposure)." ;;
        pull) bump ask "state pull prints the whole state, including secrets." ;;
        *)    bump ask "terraform state $a1 is state surgery; needs explicit human approval." ;;
      esac ;;
    workspace)
      case "$a1" in show|list|"") ;; *) bump ask "workspace $a1 changes which state is targeted." ;; esac ;;
    init)
      [[ $args =~ \ -(upgrade|migrate-state|reconfigure|force-copy) ]] && bump ask "init with -upgrade/-migrate-state/-reconfigure/-force-copy changes providers or the backend/state location." ;;
    show) [[ $args == *" -json"* ]] && bump ask "show -json prints sensitive values in plain text (https://developer.hashicorp.com/terraform/cli/commands/show). Prefer plan-risk.sh." ;;
    output|console) bump ask "terraform $sub can print sensitive values." ;;
    login|logout) bump ask "terraform $sub writes or removes credentials." ;;
  esac
done <<<"$segments"

[[ -n $decision ]] || exit 0
reason="terraform-guard: $(printf '%s ' "${reasons[@]}")"
jq -n --arg d "$decision" --arg r "$reason" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
