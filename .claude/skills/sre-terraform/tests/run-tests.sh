#!/usr/bin/env bash
# run-tests.sh: tests the scripts and hook against a throwaway terraform_data config in a
# temp dir (local state only, no cloud), then deletes it. Needs terraform 1.7+ (removed
# blocks) and jq.
# The test harness itself runs `terraform apply -auto-approve` on that throwaway local state
# to set up fixtures. The helpers under test never apply.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$here/scripts"; H="$here/hooks/terraform-guard.sh"
command -v terraform >/dev/null && command -v jq >/dev/null || { echo "need terraform and jq"; exit 1; }

W="$(mktemp -d "${TMPDIR:-/tmp}/tf-additions-test.XXXXXX")"
trap 'rm -rf -- "$W"' EXIT
OUT="$W/_out"; mkdir -p "$OUT"
SECRET1="s3cr3t-OLD-$$" SECRET2="s3cr3t-NEW-$$"
pass=0 fail=0
ok()   { pass=$((pass+1)); printf 'PASS  %s\n' "$*"; }
bad()  { fail=$((fail+1)); printf 'FAIL  %s\n' "$*"; }
expect_rc() { # expect_rc <want> <name> <logfile> -- cmd...
  local want="$1" name="$2" log="$3"; shift 4
  local rc=0; "$@" >"$log" 2>&1 || rc=$?
  [[ $rc == "$want" ]] && ok "$name (exit $rc)" || { bad "$name (exit $rc, want $want)"; sed 's/^/      /' "$log" | head -20; }
}
tfq() { terraform -chdir="$W" "$@" -no-color >/dev/null; }

# ---------- baseline config ----------
cat > "$W/vars.tf" <<V
variable "pw" {
  type      = string
  sensitive = true
  default   = "$SECRET1"
}
variable "trig" {
  type    = string
  default = "x"
}
variable "label" {
  type    = string
  default = "one"
}
V
cat > "$W/main.tf" <<'M'
resource "terraform_data" "secret" { input = var.pw }
resource "terraform_data" "replaceme" {
  input            = "v1"
  triggers_replace = [var.trig]
}
resource "terraform_data" "deleteme" { input = "bye" }
resource "terraform_data" "old_name" { input = "moving" }
resource "terraform_data" "forgetme" { input = "keep-object" }
output "label" { value = var.label }
output "pw" {
  value     = terraform_data.secret.output
  sensitive = true
}
M
terraform -chdir="$W" fmt -no-color >/dev/null
tfq init -input=false
tfq apply -input=false -auto-approve   # harness setup on throwaway local state

echo "== preflight.sh"
expect_rc 0 "preflight runs" "$OUT/preflight.log" -- "$S/preflight.sh" -C "$W"
grep -q 'backend:' "$OUT/preflight.log" && grep -q 'workspace: default' "$OUT/preflight.log" && ok "preflight shows workspace and backend" || bad "preflight content"
grep -q 'sensitive file on disk: terraform.tfstate' "$OUT/preflight.log" && ok "preflight warns about local state file" || bad "preflight state warning"
TF_LOG=TRACE TF_CLI_ARGS_plan="-input=false" "$S/preflight.sh" -C "$W" >"$OUT/preflight-env.log" 2>&1
grep -q 'TF_LOG is set' "$OUT/preflight-env.log" && grep -q 'TF_CLI_ARGS_plan is set' "$OUT/preflight-env.log" && ! grep -q -- '-input=false' "$OUT/preflight-env.log" \
  && ok "preflight flags TF_LOG / TF_CLI_ARGS by name only" || bad "preflight env warnings"

echo "== plan-risk.sh: no-change plan"
tfq plan -input=false -out="$W/noop.tfplan"
expect_rc 0 "plan-risk on no-op plan" "$OUT/risk-noop.log" -- "$S/plan-risk.sh" -C "$W" "$W/noop.tfplan"
grep -q 'RESULT: no deletes' "$OUT/risk-noop.log" && ok "no-op report complete" || bad "no-op report incomplete"

echo "== plan-risk.sh: risky plan"
cat > "$W/main.tf" <<'M'
resource "terraform_data" "secret" { input = var.pw }
resource "terraform_data" "replaceme" {
  input            = "v1"
  triggers_replace = [var.trig]
}
resource "terraform_data" "new_name" { input = "moving" }
moved {
  from = terraform_data.old_name
  to   = terraform_data.new_name
}
removed {
  from = terraform_data.forgetme
  lifecycle {
    destroy = false
  }
}
import {
  to = terraform_data.imported
  id = "imp-123"
}
resource "terraform_data" "imported" {}
resource "terraform_data" "created" { input = "hello" }
output "label" { value = var.label }
output "pw" {
  value     = terraform_data.secret.output
  sensitive = true
}
M
tfq plan -input=false -var "pw=$SECRET2" -var trig=y -var label=two -out="$W/risky.tfplan"
expect_rc 3 "plan-risk flags approval-required plan" "$OUT/risk.log" -- "$S/plan-risk.sh" -C "$W" "$W/risky.tfplan"
check() { grep -q -- "$2" "$OUT/risk.log" && ok "plan-risk: $1" || bad "plan-risk: $1 (missing '$2')"; }
check "counts"            'create=1 update=1 delete=1 replace=1 read=0 forget=1'
check "delete listed"     '- terraform_data.deleteme  \[delete_because_no_resource_config\]'
check "replace + paths"   'terraform_data.replaceme  (delete,create)  forced by: triggers_replace'
check "forget listed"     '- terraform_data.forgetme'
check "import listed"     '- terraform_data.imported'
check "moved listed"      'terraform_data.old_name -> terraform_data.new_name'
check "sensitive paths"   'terraform_data.secret  (update): input'
check "output names only" 'output.pw  \[sensitive\]'
check "result line"       'RESULT: APPROVAL REQUIRED'
grep -q 'imp-123' "$OUT/risk.log" && bad "plan-risk printed import id" || ok "plan-risk does not print import id"
"$S/plan-risk.sh" -C "$W" --json "$W/risky.tfplan" >"$OUT/risk.json" 2>&1 || true
jq -e '.approval_required == true and .counts.replace == 1 and (.imports|length) == 1' "$OUT/risk.json" >/dev/null && ok "plan-risk --json valid" || bad "plan-risk --json"
terraform -chdir="$W" show -json "$W/risky.tfplan" > "$W/risky.json"
grep -q "$SECRET2" "$W/risky.json" && ok "control: raw show -json DOES contain the secret" || bad "control: expected secret in raw json"
expect_rc 3 "plan-risk accepts JSON input on stdin" "$OUT/risk-stdin.log" -- bash -c "'$S/plan-risk.sh' - < '$W/risky.json'"
grep -q 'RESULT: APPROVAL REQUIRED' "$OUT/risk-stdin.log" && ok "stdin report complete" || bad "stdin report incomplete"
rm -f "$W/risky.json"
echo '{"format_version":"1.0","values":{}}' > "$W/state.json"
expect_rc 1 "plan-risk rejects non-plan JSON" "$OUT/risk-bad.log" -- "$S/plan-risk.sh" "$W/state.json"

echo "== plan-risk.sh: drift section (fixture following the documented JSON format)"
cat > "$W/drift-fixture.json" <<'J'
{"format_version":"1.2","terraform_version":"1.x","planned_values":{},"resource_changes":[],
 "resource_drift":[{"address":"example_bucket.logs","change":{"actions":["update"],"before":{"acl":"private"},"after":{"acl":"public-read"}}},
                   {"address":"example_instance.web","change":{"actions":["delete"],"before":{"id":"i-123"},"after":null}}],
 "output_changes":{}}
J
"$S/plan-risk.sh" --drift-only "$W/drift-fixture.json" >"$OUT/drift-fixture.log" 2>&1 || true
grep -q 'update  example_bucket.logs' "$OUT/drift-fixture.log" && grep -q 'delete  example_instance.web' "$OUT/drift-fixture.log" \
  && ! grep -q 'public-read' "$OUT/drift-fixture.log" && ok "drift listing shows addresses, no values" || bad "drift fixture listing"

echo "== drift-check.sh"
# Put the baseline config back (no pending changes), then check.
cat > "$W/main.tf" <<'M'
resource "terraform_data" "secret" { input = var.pw }
resource "terraform_data" "replaceme" {
  input            = "v1"
  triggers_replace = [var.trig]
}
resource "terraform_data" "deleteme" { input = "bye" }
resource "terraform_data" "old_name" { input = "moving" }
resource "terraform_data" "forgetme" { input = "keep-object" }
output "label" { value = var.label }
output "pw" {
  value     = terraform_data.secret.output
  sensitive = true
}
M
expect_rc 0 "drift-check: no drift" "$OUT/drift0.log" -- "$S/drift-check.sh" -C "$W"
echo 'label = "changed-outside"' > "$W/drift.tfvars"
expect_rc 2 "drift-check: root output differs from state -> drift" "$OUT/drift2.log" -- "$S/drift-check.sh" -C "$W" -- -var-file=drift.tfvars
grep -q 'output.label' "$OUT/drift2.log" && ! grep -q 'changed-outside' "$OUT/drift2.log" && ok "drift-check lists output name, not value" || bad "drift-check output listing"
expect_rc 1 "drift-check refuses -lock=false"    "$OUT/drift-r1.log" -- "$S/drift-check.sh" -C "$W" -- -lock=false
expect_rc 1 "drift-check refuses -target"        "$OUT/drift-r2.log" -- "$S/drift-check.sh" -C "$W" -- -target=terraform_data.secret
expect_rc 1 "drift-check refuses -auto-approve"  "$OUT/drift-r3.log" -- "$S/drift-check.sh" -C "$W" -- -auto-approve
echo 'resource "terraform_data" "broken" { input = nope.x }' > "$W/broken.tf"
expect_rc 1 "drift-check: config error -> exit 1" "$OUT/drift1.log" -- "$S/drift-check.sh" -C "$W"
rm -f "$W/broken.tf"
ls "${TMPDIR:-/tmp}"/tf-ro.* >/dev/null 2>&1 && bad "drift-check left temp dirs" || ok "drift-check removed its temp plan"
before_serial="$(jq .serial "$W/terraform.tfstate")"
"$S/drift-check.sh" -C "$W" -- -var-file=drift.tfvars >/dev/null 2>&1 || true
[[ "$(jq .serial "$W/terraform.tfstate")" == "$before_serial" ]] && ok "drift-check did not write state" || bad "drift-check changed state serial"
TF_CLI_ARGS_plan="-lock=false" "$S/drift-check.sh" -C "$W" >"$OUT/drift-env.log" 2>&1 && bad "dangerous TF_CLI_ARGS not refused" \
  || { grep -q 'TF_CLI_ARGS_plan injects' "$OUT/drift-env.log" && ok "scripts refuse dangerous TF_CLI_ARGS_plan"; }

echo "== tf-readonly.sh"
expect_rc 0 "tf-readonly validate"            "$OUT/ro1.log" -- "$S/tf-readonly.sh" -C "$W" validate
expect_rc 0 "tf-readonly fmt (forced -check)" "$OUT/ro2.log" -- "$S/tf-readonly.sh" -C "$W" fmt -recursive
expect_rc 0 "tf-readonly init (lockfile=readonly)" "$OUT/ro3.log" -- "$S/tf-readonly.sh" -C "$W" init
expect_rc 0 "tf-readonly state list"          "$OUT/ro4.log" -- "$S/tf-readonly.sh" -C "$W" state list
expect_rc 2 "tf-readonly plan -detailed-exitcode passes through" "$OUT/ro5.log" -- "$S/tf-readonly.sh" -C "$W" plan -detailed-exitcode -var-file=drift.tfvars
for c in "apply" "apply $W/noop.tfplan" "destroy" "refresh" "import terraform_data.x y" "state rm terraform_data.secret" \
         "state mv a b" "state push x" "state pull" "force-unlock 123" "taint terraform_data.secret" "output" "console" \
         "show -json $W/noop.tfplan" "plan -target=terraform_data.secret" "plan -replace=terraform_data.secret" "plan -destroy" \
         "plan -lock=false" "init -upgrade" "init -migrate-state" "workspace select prod" "fmt -write=true"; do
  # shellcheck disable=SC2086
  expect_rc 1 "tf-readonly refuses: $c" "$OUT/ro-refuse.log" -- "$S/tf-readonly.sh" -C "$W" $c
done
[[ "$(jq .serial "$W/terraform.tfstate")" == "$before_serial" ]] && ok "state unchanged after refusals" || bad "state changed"

echo "== terraform-guard.sh hook"
hook() { jq -n --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' | "$H" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo none; }
expect_hook() { local got; got="$(hook "$2")"; [[ ${got:-none} == "$1" ]] && ok "hook $1: $2" || bad "hook want $1 got ${got:-none}: $2"; }
expect_hook deny "terraform apply"
expect_hook deny "terraform apply -auto-approve tfplan"
expect_hook deny "cd infra && terraform -chdir=prod apply -var-file=prod.tfvars"
expect_hook deny "terraform destroy"
expect_hook deny "terraform apply -destroy tfplan"
expect_hook deny "terraform refresh"
expect_hook deny "terraform force-unlock -force 1234"
expect_hook deny "terraform plan -out=tfplan && terraform apply -auto-approve"
expect_hook ask  "terraform apply tfplan"
expect_hook ask  "terraform -chdir=envs/prod apply tfplan"
expect_hook ask  "terraform import aws_x.y id"
expect_hook ask  "terraform state rm module.a.b"
expect_hook ask  "terraform state mv a b"
expect_hook ask  "terraform state show aws_db.main"
expect_hook ask  "terraform force-unlock 1234"
expect_hook ask  "terraform plan -replace=aws_instance.web -out=tfplan"
expect_hook ask  "terraform plan -target=module.x"
expect_hook ask  "terraform plan -lock=false"
expect_hook ask  "terraform show -json tfplan | jq ."
expect_hook ask  "terraform output -raw db_password"
expect_hook ask  "terraform workspace select prod"
expect_hook ask  "terraform init -upgrade"
expect_hook ask  "TF_CLI_ARGS_plan=-lock=false terraform plan"
expect_hook none "terraform plan -input=false -out=tfplan"
expect_hook none "terraform show -no-color tfplan"
expect_hook none "terraform state list"
expect_hook none "terraform fmt -check -recursive && terraform validate"
expect_hook none "ls -la"

echo "== secrets never printed by helpers"
if grep -rl -e "$SECRET1" -e "$SECRET2" "$OUT" >/dev/null; then bad "a secret appeared in helper output: $(grep -rl -e "$SECRET1" -e "$SECRET2" "$OUT" | xargs -n1 basename | tr '\n' ' ')"
else ok "no secret value in any captured helper output ($(ls "$OUT" | wc -l) logs)"; fi

echo
echo "RESULT: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
