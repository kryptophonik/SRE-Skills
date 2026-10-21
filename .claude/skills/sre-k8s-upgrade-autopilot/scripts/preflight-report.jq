# Human-readable report from preflight.json.
"Kubernetes upgrade preflight: context \(.context), \(.cluster.server_version) -> 1.\(.cluster.target_minor) (provider: \(.provider))",
"Generated \(.generated_at). Verdict: \(.verdict)  (blockers \(.summary.blockers), warnings \(.summary.warnings), info \(.summary.info))",
"",
"Node pools:",
(.cluster.node_pools[] | "  \(.pool): \(.nodes) node(s), kubelet \(.kubelet_versions | join(", "))"),
"",
"Removed-API window checked: \(if (.removed_api_window | length) == 0 then "none (no upstream removals between these versions)" else (.removed_api_window | join("; ")) end)",
"",
(["BLOCKER", "WARN", "INFO", "OK"][] as $s
  | [.findings[] | select(.severity == $s)] as $f
  | if ($f | length) == 0 then empty else
      "\($s) (\($f | length))",
      ($f[] | "  [\(.category)] \(.object)\n      \(.message)\(if .fix != "" then "\n      fix: \(.fix)" else "" end)\(if .ref != "" then "\n      ref: \(.ref)" else "" end)"),
      ""
    end)
