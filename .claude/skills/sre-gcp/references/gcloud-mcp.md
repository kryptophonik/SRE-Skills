# gcloud MCP server: read-only setup

Sources (all fetched 2026-10-16; GitHub files show no date):
- https://raw.githubusercontent.com/googleapis/gcloud-mcp/main/README.md
- https://raw.githubusercontent.com/googleapis/gcloud-mcp/main/doc/denylist.md
- https://raw.githubusercontent.com/googleapis/gcloud-mcp/main/packages/gcloud-mcp/src/index.ts
- https://docs.cloud.google.com/mcp/overview (Last updated 2026-10-16 UTC)

## Why the defaults aren't read-only
- `run_gcloud_command` runs any gcloud command with the active account's permissions.
- The built-in `default_deny` only blocks interactive and remote-shell commands: `compute start-iap-tunnel`, `compute connect-to-serial-port`, `compute tpus tpu-vm ssh`, `compute tpus queued-resources ssh`, `compute ssh`, `cloud-shell ssh`, `workstations ssh`, `app instances ssh`, `interactive`, `meta`. It does **not** block create, update, delete, resize or set-iam-policy.
- The separate **storage** server (`delete_object`, `write_object`, `create_bucket`, `delete_bucket`, ...) and **backupdr** server (`csql_restore`, `restore_backup`, `delete_backup`, ...) expose write tools. Don't install them for read-only triage, or put every write tool behind approval.
- The **observability** server's tools are all `list_*` and `get_*`.

## Allowlist
Pass `-c` with an absolute path to [`gcloud-mcp-readonly-allowlist.json`](gcloud-mcp-readonly-allowlist.json):

```json
{ "mcpServers": {
"gcloud": { "command": "npx", "args": ["-y", "@google-cloud/gcloud-mcp@<pinned-version>", "-c", "/ABS/PATH/gcloud-mcp-readonly-allowlist.json"] }
} }
```

Rules from denylist.md:
- The file holds **either** `allow` or `deny`, not both.
- Any command not in the allowlist is refused, and the default denylist still applies.
- An allow entry covers only that release track, so `monitoring policies list` allows the GA command, not `alpha monitoring policies list`.

`container clusters get-credentials` is left out on purpose because it writes the local kubeconfig. Run it yourself after approval.

## Least privilege
Even with the allowlist, run the server as a viewer service account through impersonation (see [iam-readonly-roles.md](iam-readonly-roles.md)), as the gcloud-mcp README recommends. Google's remote MCP servers are controlled by IAM (`roles/mcp.toolUser`, per the overview page).
