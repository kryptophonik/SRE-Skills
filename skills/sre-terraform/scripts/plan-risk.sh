#!/usr/bin/env bash
# plan-risk.sh: read-only risk summary of a saved Terraform plan. It never prints values.
#
# Usage:
#   plan-risk.sh [-C DIR] [--json] [--drift-only] <plan-file | plan.json | ->
#
#   <plan-file>  a binary plan from `terraform plan -out=FILE`; read with `terraform show -json`
#                (run inside the initialized root module, or pass -C DIR)
#   plan.json    output you already have from `terraform show -json FILE` (starts with '{')
#   -            read plan JSON from stdin
#   --json       print a machine-readable summary (counts and addresses only)
#   --drift-only print only the drift section (used by drift-check.sh)
#
# Exit codes: 0 = no approval-required changes, 1 = error,
#             3 = approval-required changes found (delete, replace, forget, import,
#                 or the plan errored or is incomplete)
#
# What it reports: counts by action (create, update, delete, replace, read, forget, no-op);
# lists of deletes and replaces (with replace_paths attribute names and action_reason),
# imports, moved addresses (previous_address), removed/forget, deposed objects;
# changes that touch sensitive attributes (attribute paths only); output changes
# (names only); and resource_drift.
#
# Values are never printed: no before, after, or importing.id. Attribute paths, resource
# addresses (including for_each keys), and output names are shown.
#
# Docs: https://developer.hashicorp.com/terraform/internals/json-format
#       https://developer.hashicorp.com/terraform/cli/commands/show  (-json prints sensitive values in plain text)
#       https://developer.hashicorp.com/terraform/cli/commands/plan
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

dir="" mode="text" drift_only=false src=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -C) [[ $# -ge 2 ]] || die "-C needs a directory"; dir="$2"; shift 2 ;;
    --json) mode="json"; shift ;;
    --drift-only) drift_only=true; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    -*) [[ $1 == "-" ]] && { src="-"; shift; continue; }; die "unknown option: $1" ;;
    *) [[ -z $src ]] || die "only one plan file allowed"; src="$1"; shift ;;
  esac
done
[[ -n $src ]] || die "usage: plan-risk.sh [-C DIR] [--json] [--drift-only] <plan-file|plan.json|->"
require_cmd jq

# Load plan JSON into memory only (never write it to disk; it contains secrets).
if [[ $src == "-" ]]; then
  plan_json="$(cat)"
elif [[ -f $src ]] && [[ "$(head -c1 -- "$src")" == "{" ]]; then
  plan_json="$(cat -- "$src")"
else
  require_cmd terraform
  guard_tf_cli_args
  init_tf "$dir"
  [[ -n $dir || -f $src ]] || die "plan file not found: $src"
  plan_json="$("${TF[@]}" show -json -no-color "$src")" || die "terraform show -json failed (run inside the initialized root module, or use -C DIR)"
fi

printf '%s' "$plan_json" | jq -e 'type == "object" and has("format_version") and (has("planned_values") or has("resource_changes") or has("prior_state"))' >/dev/null 2>&1 \
  || die "input is not Terraform plan JSON (a state file or other JSON?)"
printf '%s' "$plan_json" | jq -e 'has("resource_changes") or has("output_changes") or has("resource_drift") or has("planned_values")' >/dev/null \
  || die "input has no plan sections; is it a state file?"

# The jq program reads only actions, addresses, *_sensitive masks, and replace_paths.
# It compares before/after values at sensitive paths to decide whether they changed,
# but never outputs them.
JQ_LIB='
def kind:
  (.change.actions // []) as $a
  | if   $a == ["no-op"] then "no-op"
    elif $a == ["create"] then "create"
    elif $a == ["read"] then "read"
    elif $a == ["update"] then "update"
    elif $a == ["delete"] then "delete"
    elif ($a == ["delete","create"] or $a == ["create","delete"]) then "replace"
    elif ($a | index("forget")) != null then "forget"
    else ($a | join(",")) end;
def pathstr: if length == 0 then "(whole value)" else map(tostring) | join(".") end;
def sens_paths($m):
  if $m == true then [[]]
  elif ($m | type) == "object" or ($m | type) == "array" then [ $m | paths(. == true) ]
  else [] end;
# Sensitive paths whose value changes (created, deleted, changed, or unknown after apply).
def changed_sensitive:
  .change as $c
  | (sens_paths($c.before_sensitive // false) + sens_paths($c.after_sensitive // false) | unique) as $ps
  | [ $ps[] as $p
      | select(
          (try ($c.before | getpath($p)) catch "__x__") != (try ($c.after | getpath($p)) catch "__x__")
          or ((try ($c.after_unknown | getpath($p)) catch false) == true) )
      | $p | pathstr ];
def rc: (.resource_changes // []);
def addr_label: .address + (if .deposed then " (deposed " + (.deposed|tostring) + ")" else "" end);
def summary:
  {
    terraform_version, format_version,
    errored: (.errored // false),
    applyable: (if has("applyable") then .applyable else null end),
    complete: (if has("complete") then .complete else null end),
    counts: (reduce (rc[] | kind) as $k ({create:0,update:0,delete:0,replace:0,read:0,forget:0,"no-op":0}; .[$k] += 1)),
    deletes:  [ rc[] | select(kind == "delete")  | {address: addr_label, reason: (.action_reason // null)} ],
    replaces: [ rc[] | select(kind == "replace") | {address: addr_label, order: (.change.actions|join(",")),
                 replace_paths: [ (.change.replace_paths // [])[] | pathstr ], reason: (.action_reason // null)} ],
    forgets:  [ rc[] | select(kind == "forget")  | addr_label ],
    imports:  [ rc[] | select(.change.importing != null) | {address, action: kind} ],
    moved:    [ rc[] | select(.previous_address != null) | {from: .previous_address, to: .address, action: kind} ],
    sensitive_changes: [ rc[] | select(kind != "no-op" and kind != "read")
                          | {address, action: kind, paths: changed_sensitive} | select(.paths | length > 0) ],
    output_changes: [ (.output_changes // {}) | to_entries[] | select(.value.actions != ["no-op"])
                      | {name: .key, actions: (.value.actions|join(",")),
                         sensitive: ((.value.before_sensitive == true) or (.value.after_sensitive == true))} ],
    drift: [ (.resource_drift // [])[] | {address, action: kind} ],
    deferred: ((.deferred_changes // []) | length)
  }
  | .approval_required = (
      .errored or (.complete == false) or
      ((.deletes|length) + (.replaces|length) + (.forgets|length) + (.imports|length)) > 0 );
'

summary_json="$(printf '%s' "$plan_json" | jq -c "$JQ_LIB summary")" || die "failed to summarize plan JSON"
unset plan_json

if [[ $mode == "json" ]]; then
  printf '%s\n' "$summary_json" | jq . || die "jq failed"
else
  printf '%s\n' "$summary_json" | jq -r --argjson drift_only "$drift_only" '
    def lst(f): if length == 0 then "  (none)" else map("  - " + f) | join("\n") end;
    if $drift_only then
      "Drift (objects changed outside Terraform): \(.drift|length)",
      (.drift | lst("\(.action)  \(.address)")),
      "Output value changes: \(.output_changes|length)",
      (.output_changes | lst("\(.actions)  output.\(.name)" + (if .sensitive then "  [sensitive]" else "" end)))
    else
      "Terraform \(.terraform_version // "?")  (plan format \(.format_version))  errored=\(.errored)  applyable=\(.applyable)  complete=\(.complete)",
      "Counts: create=\(.counts.create) update=\(.counts.update) delete=\(.counts.delete) replace=\(.counts.replace) read=\(.counts.read) forget=\(.counts.forget) no-op=\(.counts["no-op"])"
        + (if .deferred > 0 then " deferred=\(.deferred)" else "" end),
      "",
      "DELETES (\(.deletes|length)):",  (.deletes  | lst(.address + (if .reason then "  [" + .reason + "]" else "" end))),
      "REPLACES (\(.replaces|length)):", (.replaces | lst(.address + "  (" + .order + ")"
          + (if (.replace_paths|length) > 0 then "  forced by: " + (.replace_paths|join(", ")) else "" end)
          + (if .reason then "  [" + .reason + "]" else "" end))),
      "REMOVED / FORGET (state only, object kept) (\(.forgets|length)):", (.forgets | lst(.)),
      "IMPORTS (\(.imports|length)):", (.imports | lst(.address + "  (" + .action + ")")),
      "MOVED (\(.moved|length)):", (.moved | lst(.from + " -> " + .to + "  (" + .action + ")")),
      "SENSITIVE ATTRIBUTE CHANGES, paths only (\(.sensitive_changes|length)):",
        (.sensitive_changes | lst(.address + "  (" + .action + "): " + (.paths|join(", ")))),
      "OUTPUT CHANGES, names only (\(.output_changes|length)):",
        (.output_changes | lst(.actions + "  output." + .name + (if .sensitive then "  [sensitive]" else "" end))),
      "DRIFT seen during refresh (\(.drift|length)):", (.drift | lst(.action + "  " + .address)),
      "",
      (if .approval_required
        then "RESULT: APPROVAL REQUIRED. Destructive, state-changing, or incomplete plan. Stop, show this summary to a human, and wait for explicit approval before any apply."
        else "RESULT: no deletes, replaces, forgets, or imports. Normal change review still applies; apply only this saved plan file after approval." end)
    end' || die "jq failed while formatting the report"
fi

if printf '%s' "$summary_json" | jq -e '.approval_required' >/dev/null; then exit 3; fi
exit 0
