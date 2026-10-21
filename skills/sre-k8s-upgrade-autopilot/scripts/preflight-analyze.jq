# Turns the trimmed inventory bundle into findings and a go/no-go verdict.
# Severity: BLOCKER (stop), WARN (needs a human decision), INFO (context), OK (checked and fine).

def SKEW: "https://kubernetes.io/releases/version-skew-policy/";
def DEPR: "https://kubernetes.io/docs/reference/using-api/deprecation-guide/";
def PDB: "https://kubernetes.io/docs/tasks/run-application/configure-pdb/";
def DRAIN: "https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/";
def HOOK: "https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/";
def METRIC: "https://kubernetes.io/blog/2020/09/03/warnings/";
def SSA: "https://kubernetes.io/docs/reference/using-api/server-side-apply/";
def OPPDB: "https://cloudnative-pg.io/documentation/1.24/kubernetes_upgrade/";
def ZONE: "https://kubernetes.io/docs/concepts/storage/persistent-volumes/";

def minor: (capture("^v?1\\.(?<m>[0-9]+)") // {m: "-1"}) | .m | tonumber;
def tag: split("@")[0] | if test(":[^/:]+$") then sub("^.*:"; "") else "" end;
def arr: if type == "array" then . else [] end;
def failed: type == "object" and has("error");
def f(sev; cat; obj; msg; fix; ref): {severity: sev, category: cat, object: obj, message: msg, fix: fix, ref: ref};
def unchecked(name; x): if (x | failed) then [f("WARN"; "coverage"; name; "Could not check \(name): \(x.error)"; "Grant get/list on this resource to the preflight identity, or check it by hand before the upgrade."; "")] else [] end;
def pct0: . == 0 or . == "0%" or . == "0";
def sevrank(x): {BLOCKER: 0, WARN: 1, INFO: 2, OK: 3}[x];
# Is a support date (YYYY-MM-DD, YYYY-MM or YYYY-Qn) already behind today (YYYY-MM-DD)?
def past($d; $today):
  if ($d | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) then $d < $today
  elif ($d | test("^[0-9]{4}-[0-9]{2}$")) then $d < $today[0:7]
  elif ($d | test("^[0-9]{4}-Q[1-4]$")) then (($d[0:4] | tonumber) * 4 + ($d[6:7] | tonumber)) < (($today[0:4] | tonumber) * 4 + ((($today[5:7] | tonumber) - 1) / 3 | floor) + 1)
  else false end;
# First day a support date could fall on: YYYY-MM -> YYYY-MM-01, YYYY-Qn -> first day of that quarter.
def dstart($d):
  if ($d | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) then $d
  elif ($d | test("^[0-9]{4}-[0-9]{2}$")) then $d + "-01"
  elif ($d | test("^[0-9]{4}-Q[1-4]$")) then "\($d[0:4])-\((($d[6:7] | tonumber) - 1) * 3 + 1 | tostring | if length == 1 then "0" + . else . end)-01"
  else "9999-12-31" end;
# Ends after the look-ahead horizon (conservative for month- and quarter-only dates)?
def lasts($d; $h): $d != null and dstart($d) > $h;
# Not ended yet, but could end on or before the horizon.
def ending($d; $today; $h): $d != null and (past($d; $today) | not) and dstart($d) <= $h;
# Price notes never read as a current quote.
def pricenote($sd; $p): " Prices as checked \($sd.checked); confirm current pricing at \($sd.sources[$p + "_pricing"])."; 
# "ns/name" for namespaced objects, "name" for cluster-scoped ones (kubent prints <undefined> for those).
def objname(ns; name): if (ns == null or ns == "" or ns == "<undefined>") then name else "\(ns)/\(name)" end;

. as $b
| ($b.version.server | minor) as $cur
| $b.target as $t
| ($b.version.client // "" | minor) as $cli
| ($b.apiversions | arr) as $served
| ($b.version.server) as $sv
| (
    if ($sv | test("-eks-")) or any($b.nodes | arr | .[]; .provider_id | startswith("aws://")) then "eks"
    elif ($sv | test("-gke\\.")) or any($b.nodes | arr | .[]; .provider_id | startswith("gce://")) then "gke"
    elif any($b.nodes | arr | .[]; .provider_id | startswith("azure://")) then "aks"
    elif any($b.nodes | arr | .[]; .provider_id | startswith("kind://")) then "kind"
    else "unknown" end
  ) as $provider
| (if ($provider | IN("eks", "gke", "aks")) then "references/\($provider).md" else "your provider's upgrade docs" end) as $pref

# ---------- version skew ----------
| ([
    if $t <= $cur then f("BLOCKER"; "skew"; "control plane"; "Target 1.\($t) is not newer than the control plane (\($sv))."; "Pick the next minor version, 1.\($cur + 1)."; SKEW)
    elif $t > $cur + 1 then f("BLOCKER"; "skew"; "control plane"; "Target 1.\($t) skips minor versions; the control plane is at \($sv)."; "Upgrade one minor at a time: run this preflight for 1.\($cur + 1) first. (AKS LTS-to-LTS is the documented exception; see references/aks.md.)"; SKEW)
    else f("OK"; "skew"; "control plane"; "Control plane \($sv) to 1.\($t) is a single minor step."; ""; SKEW) end
  ]
  + [ $b.nodes | arr | .[] | (.kubelet | minor) as $k | . as $n
      | (if $k < 25 then 2 else 3 end) as $max
      | if $k > $cur then f("BLOCKER"; "skew"; "node/\($n.name)"; "kubelet \($n.kubelet) is newer than the control plane \($sv)."; "Unsupported state; fix the node before any upgrade."; SKEW)
        elif $t - $k > $max then f("BLOCKER"; "skew"; "node/\($n.name)"; "kubelet \($n.kubelet) would be \($t - $k) minors behind a 1.\($t) control plane (max \($max))."; "Upgrade pool \($n.pool | if . == "" then "(unlabelled)" else . end) to 1.\($cur) before the control plane."; SKEW)
        elif $k < $cur then f("WARN"; "skew"; "node/\($n.name)"; "kubelet \($n.kubelet) is behind the control plane \($sv) (allowed, but EKS asks for matching managed nodes before a control-plane update)."; "Bring pool \($n.pool | if . == "" then "(unlabelled)" else . end) to 1.\($cur) first."; SKEW)
        else empty end ]
  + ( [ $b.daemonsets | arr | .[] | select(.name == "kube-proxy") | .images[] | select(test("kube-proxy")) | tag | select(. != "") ] as $kp
      | [ $kp[] | minor as $m | (if $m < 25 then 2 else 3 end) as $max
          | if $m > $cur then f("BLOCKER"; "skew"; "daemonset/kube-system/kube-proxy"; "kube-proxy \(.) is newer than the control plane."; "Fix kube-proxy before the upgrade."; SKEW)
            elif $t - $m > $max then f("BLOCKER"; "skew"; "daemonset/kube-system/kube-proxy"; "kube-proxy \(.) would be \($t - $m) minors behind 1.\($t) (max \($max))."; "Upgrade kube-proxy to 1.\($cur) first."; SKEW)
            else empty end ] )
  + [ if $cli >= 0 and ($cli < $t - 1 or $cli > $t + 1) then f("INFO"; "skew"; "kubectl client"; "kubectl \($b.version.client) is outside the supported +/-1 minor window for 1.\($t)."; "Install a kubectl within one minor of 1.\($t) for the post-upgrade steps."; SKEW) else empty end ]
  ) as $skew

# ---------- nodes ----------
| ( unchecked("nodes"; $b.nodes)
    + [ $b.nodes | arr | .[] | select(.ready != "True") | f("BLOCKER"; "health"; "node/\(.name)"; "Node is not Ready (Ready=\(.ready))."; "Fix or replace the node before upgrading; an unhealthy cluster hides upgrade regressions."; DRAIN) ]
    + [ $b.nodes | arr | .[] | select(.unschedulable) | f("WARN"; "health"; "node/\(.name)"; "Node is cordoned."; "Confirm why before the upgrade; a cordoned node shrinks drain headroom."; DRAIN) ]
  ) as $health

# ---------- removed APIs ----------
| ( $b.removed | map(select(.removed_in > $cur and .removed_in <= $t)) ) as $window
| ( [ $window[] | . as $r | "\($r.group)/\($r.version)" as $gv | ($r.list_as // "\($r.resource).\($r.group)") as $key
      | ($b.objects[$key]) as $objs
      | if ($objs | failed) then f("WARN"; "removed-api"; $key; "Could not list \($key) to look for \($gv) writers: \($objs.error)"; (if $key == "podsecuritypolicies.policy" then "Add the commented-out podsecuritypolicies rule in references/rbac-preflight.yaml (PodSecurityPolicy section) to the preflight role for this 1.24 to 1.25 run, or accept the gap and check PSP use by hand or with your provider insights." else "Check by hand or with your provider insights." end); DEPR)
        # Stored objects are kept version-independently and are served through the new version after the upgrade.
        # What matters is whether a client still writes them through the removed version: the manifest in the
        # last-applied annotation, or a field manager whose only entries use the removed version. A manager that
        # also has an entry for another version has moved on; its old entry just still owns fields and stays in
        # managedFields (harmless), so it is INFO, not a blocker.
        else ($objs | arr | .[] | . as $o
              | ([ .writers[]? | select(.api_version == $gv) | .manager ] | unique) as $old
              | ([ $old[] | . as $m | select(all($o.writers[]; .manager != $m or .api_version == $gv)) ]) as $live
              | if .last_applied == $gv or ($live | length) > 0 then
                  f("BLOCKER"; "removed-api"; "\($r.kind)/\(objname(.ns; .name))";
                    "Still written through \($gv), which 1.\($r.removed_in) no longer serves (\([ (if .last_applied == $gv then "last-applied manifest" else empty end), ($live[] | "field manager \(.)") ] | join(", ")))."; "Change the manifest, chart or controller that writes it to \($r.use) and re-apply before the upgrade."; DEPR)
                  + {_src: "object check", _gv: $gv, _kind: $r.kind}
                elif ($old | length) > 0 then
                  f("INFO"; "removed-api"; "\($r.kind)/\(objname(.ns; .name))";
                    "Stale managedFields entry for \($gv) from \($old | join(", ")): that manager has since written it through another version, so the old entry only records field ownership. kubectl get --show-managed-fields keeps showing it; it is harmless for the upgrade."; "No action needed for the upgrade. If you want the entry gone, the server-side apply docs describe resetting managedFields; that is a write and needs its own approval."; SSA)
                  + {_src: "object check", _gv: $gv, _kind: $r.kind}
                else empty end)
        end ] ) as $removed_objs
| ( [ ($b.kubent | if type == "array" then .[] else empty end) | select(type == "object")
      | ((.RuleSet // "") | (capture("removed in (?<v>[0-9.]+)") // {v: ""}) | .v | minor) as $rm
      | f(if $rm >= 0 and $rm <= $t then "BLOCKER" else "INFO" end; "removed-api"; "\(.Kind // "?")/\(objname(.Namespace; .Name // "?"))";
          "kubent: \(.ApiVersion // "?") (\(.RuleSet // "")); replace with \(.ReplaceWith // "?")."; "Migrate the manifest, chart or controller to \(.ReplaceWith // "the replacement API") and re-apply before the upgrade."; DEPR)
        + {_src: "kubent", _gv: (.ApiVersion // ""), _kind: (.Kind // "")} ]
    + [ ($b.pluto | if type == "object" then (.items // [])[] else empty end)
      | select(.removed == true or .deprecated == true)
      | ((.api["removed-in"] // "") | minor) as $rm
      | f(if $rm >= 0 and $rm <= $t then "BLOCKER" else "INFO" end; "removed-api"; "\(.api.kind // "?")/\(objname(.namespace; .name // "?"))"; "pluto: \(.api.version // "?") \(if $rm >= 0 then "removed in 1.\($rm)" else "deprecated" end); replacement \(.api["replacement-api"] // "?")."; "Migrate the manifest or chart."; DEPR)
        + {_src: "pluto", _gv: (.api.version // ""), _kind: (.api.kind // "")} ] ) as $tools
# One finding per object: the object check, kubent and pluto often report the same object.
| ( [ ($removed_objs + $tools) | map(select(has("_src"))) | group_by(.object)[]
      | sort_by(sevrank(.severity), (if ._src == "object check" then 0 else 1 end)) as $g
      | $g[0] + {sources: [ "object check", "kubent", "pluto" ] | map(. as $x | select(any($g[]; ._src == $x)))}
      | if (.sources | length) > 1 then .message += " Reported by: \(.sources | join(", "))." else . end ] ) as $merged
# apiserver_requested_deprecated_apis counts requests since each API server instance started, so it stays set after a
# client is fixed. It is folded into the object finding when one exists; otherwise it stands alone and stays a BLOCKER
# until the operator confirms current traffic is gone (--deprecated-traffic-checked).
| ( if ($b.metric | failed) then {fold: [], alone: [f("INFO"; "removed-api"; "apiserver_requested_deprecated_apis"; "Metric not available: \($b.metric.error)"; "Use the provider's upgrade insights (\($pref)) for request-level evidence."; METRIC)]}
    else [ $b.metric | arr | .[] | select(.removed_release != null and .removed_release != "") | (.removed_release | minor) as $rr
           | "\(if .group == "" then "" else .group + "/" end)\(.version)" as $mgv
           | . as $m | ([ $b.removed[] | select(.group == $m.group and .version == $m.version and .resource == $m.resource) | .kind ][0] // "") as $mkind
           | "\($mgv) \(.resource)\(if (.subresource // "") != "" then "/" + .subresource else "" end)" as $what
           | {gv: $mgv, kind: $mkind, what: $what, rr: $rr} ]
      | . as $hits
      | {fold: [ $hits[] | select(.rr <= $t) ],
         alone: [ $hits[] | . as $h
                  | if $h.rr > $t then f("INFO"; "removed-api"; $h.what; "Deprecated API in use; removed in 1.\($h.rr), after this upgrade."; "Plan the migration before 1.\($h.rr)."; METRIC)
                    elif any($merged[]; ._gv == $h.gv and ._kind == $h.kind and .severity == "BLOCKER") then empty
                    elif $b.traffic_ok == true then f("WARN"; "removed-api"; $h.what; "The deprecated-API counter shows requests to \($h.what) (removed in 1.\($h.rr)) since the API server started. The operator confirmed with --deprecated-traffic-checked that no current client still calls it; the counter itself only resets when the API server restarts."; "Keep the audit-log or insights evidence with the change record."; METRIC)
                    else f("BLOCKER"; "removed-api"; $h.what; "Clients requested \($h.what) since the API server started; it is removed in 1.\($h.rr). This counter is cumulative since each API server instance started, so it does not clear after a fix."; "Find and fix the caller: the audit log (annotation k8s.io/deprecated; check userAgent and requestReceivedTimestamp) or the provider's insights. Once they show no requests after the fix, re-run with --deprecated-traffic-checked. On self-managed clusters an API server restart also resets the counter."; METRIC) end ]}
    end ) as $mres
| ( [ $merged[] | . as $o
      | ($o.severity == "BLOCKER" and ([ $mres.fold[] | select(.gv == $o._gv and .kind == $o._kind) ] | length > 0)) as $hit
      | if $hit then .sources += ["deprecated-API metric"] | .message += " The API server's deprecated-API counter also shows requests to this API." else . end
      | del(._src, ._gv, ._kind) ]
    + [ $removed_objs[] | select(has("_src") | not) ]
    + $mres.alone ) as $removed

# ---------- support status of the target and the current minor (references/support-status.json) ----------
# LOOKAHEAD: a minor whose support ends within this many days is treated as already ending: it is never the
# end of a hop path, and the current minor gets a deadline warning.
| ($b.now[0:10]) as $today
| 30 as $LOOKAHEAD
| (($today + "T00:00:00Z" | fromdateiso8601) + $LOOKAHEAD * 86400 | strftime("%Y-%m-%d")) as $h
| ($b.support // {}) as $sd
| "1.\($t)" as $tk
| "1.\($cur)" as $ck
| ( if ($sd | has("upstream_eol") | not) then [f("INFO"; "support"; $tk; "references/support-status.json was not loaded; support status not checked."; "Check \("https://kubernetes.io/releases/") and your provider's version calendar by hand."; "https://kubernetes.io/releases/")]
    else
      ($sd.upstream_eol[$tk]) as $ueol
      | ( [ $sd.upstream_eol | to_entries[] | select((.key | minor) > $t and lasts(.value; $h)) | .key | minor ] | min ) as $usup
      | ( if $usup != null then " The oldest upstream minor with more than \($LOOKAHEAD) days of support left is 1.\($usup), so plan further hops one minor at a time: \([range($t + 1; $usup + 1) | "1.\(.)"] | join(" -> "))." else "" end ) as $uhops
      | ( if $ueol == null then [f("INFO"; "support"; $tk; "1.\($t) is not in references/support-status.json (checked \($sd.checked))."; "Check its upstream end-of-life date before planning."; $sd.sources.upstream)]
          elif past($ueol; $today) then [f("WARN"; "support"; $tk;
            "1.\($t) reached upstream end of life on \($ueol) (dates checked \($sd.checked)): no more upstream patches.\($uhops)";
            "Plan the whole path, not just this hop; upgrade 1.\($t) only as a step."; $sd.sources.upstream)]
          elif ending($ueol; $today; $h) then [f("WARN"; "support"; $tk;
            "1.\($t) reaches upstream end of life on \($ueol), within \($LOOKAHEAD) days (dates checked \($sd.checked)).\($uhops)";
            "Plan the next hops now; treat 1.\($t) as a step."; $sd.sources.upstream)]
          else [] end )
      + ( if ($provider | IN("eks", "gke", "aks")) | not then []
          else ($provider | ascii_upcase) as $P | ($sd[$provider] // {}) as $pv | ($pv.versions // {}) as $vers | ($vers[$tk]) as $v | ($vers[$ck]) as $cv
            | ( [ $vers | to_entries[] | select((.key | minor) > $t and lasts(.value.end_standard; $h)) | .key | minor ] | min ) as $psup
            | ( if $psup != null then " The oldest minor with more than \($LOOKAHEAD) days of \($P) standard support left is 1.\($psup); path: \([range($t + 1; $psup + 1) | "1.\(.)"] | join(" -> ")), one minor per hop." else "" end ) as $hops
            # target minor
            | ( if $v == null then [f("INFO"; "support"; "\($P) \($tk)"; "1.\($t) is not in the \($P) table in references/support-status.json (checked \($sd.checked))."; "Check the provider's version calendar."; $sd.sources[$provider])]
                elif $provider == "aks" then
                  if past($v.end_standard; $today) and past($v.end_lts; $today) then [f("WARN"; "support"; "AKS \($tk)"; "AKS support for 1.\($t) ended (community \($v.end_standard), LTS \($v.end_lts)); AKS may not offer it as a target at all.\($hops)"; "Run az aks get-upgrades for this cluster and plan the hops it offers."; $sd.sources.aks)]
                  elif past($v.end_standard; $today) then [f("WARN"; "support"; "AKS \($tk)"; "AKS community support for 1.\($t) ended \($v.end_standard). Only LTS clusters (Premium tier, about $\($pv.per_cluster_hour_usd.lts)/cluster-hour vs $\($pv.per_cluster_hour_usd.standard) Standard) keep it, until \($v.end_lts); otherwise AKS may not offer it as a target.\($hops)\(pricenote($sd; "aks"))"; "Check az aks get-upgrades before the window; without LTS, plan the hops to a supported minor."; $sd.sources.aks)]
                  elif ending($v.end_standard; $today; $h) then [f("WARN"; "support"; "AKS \($tk)"; "AKS community support for 1.\($t) ends \($v.end_standard), within \($LOOKAHEAD) days (dates checked \($sd.checked)).\($hops)"; "Plan the next hop now."; $sd.sources.aks)]
                  else [] end
                elif past($v.end_extended; $today) then [f("WARN"; "support"; "\($P) \($tk)"; "1.\($t) is past the end of extended support on \($P) (\($v.end_extended)); the provider may not accept it as a target.\($hops)"; "Check the versions the provider offers for this cluster and plan the hops."; $sd.sources[$provider])]
                elif past($v.end_standard; $today) then [f("WARN"; "support"; "\($P) \($tk)"; "1.\($t) is in \($P) extended support (standard ended \($v.end_standard), extended ends \($v.end_extended)). Extended-support charges continue after this upgrade (about $\($pv.per_cluster_hour_usd.extended) vs $\($pv.per_cluster_hour_usd.standard) per cluster-hour).\(pricenote($sd; $provider))\($hops)\(if $provider == "gke" then " On GKE only Extended-channel clusters stay on it; others are auto-upgraded." else "" end)"; "Budget for the extended rate until the cluster reaches a standard-support minor, and schedule the next hops now."; $sd.sources[$provider])]
                elif ending($v.end_standard; $today; $h) then [f("WARN"; "support"; "\($P) \($tk)"; "\($P) standard support for 1.\($t) ends \($v.end_standard), within \($LOOKAHEAD) days (dates checked \($sd.checked)).\($hops)"; "Plan the next hop now."; $sd.sources[$provider])]
                else [] end )
            # current minor: deadlines that may land before or around the change window
            + ( if $cv == null or $cur == $t then []
                elif $provider == "aks" then
                  if ending($cv.end_lts; $today; $h) then [f("WARN"; "support"; "AKS \($ck) (current)"; "The current minor 1.\($cur) loses AKS LTS support in \($cv.end_lts), within \($LOOKAHEAD) days of \($today) (dates checked \($sd.checked)); after that AKS no longer supports it at all."; "Finish this upgrade before \($cv.end_lts); check az aks get-upgrades now."; $sd.sources.aks_lts)]
                  elif ending($cv.end_standard; $today; $h) then [f("WARN"; "support"; "AKS \($ck) (current)"; "AKS community support for the current minor 1.\($cur) ends \($cv.end_standard), within \($LOOKAHEAD) days of \($today) (dates checked \($sd.checked)). Clusters not on LTS (Premium tier, about $\($pv.per_cluster_hour_usd.lts)/cluster-hour) are then out of support.\(pricenote($sd; "aks"))"; "Finish this upgrade before \($cv.end_standard)."; $sd.sources.aks)]
                  else [] end
                elif ending($cv.end_extended; $today; $h) then [f("WARN"; "support"; "\($P) \($ck) (current)"; "Extended support for the current minor 1.\($cur) on \($P) ends \($cv.end_extended), within \($LOOKAHEAD) days of \($today) (dates checked \($sd.checked)). After that the provider upgrades the control plane automatically\(if $provider == "eks" then ", and a cluster upgraded that way can't be rolled back" else "" end)."; "Finish this upgrade before \($cv.end_extended), on your schedule rather than the provider's; confirm the date on the linked page."; $sd.sources[$provider])]
                elif ending($cv.end_standard; $today; $h) then [f("WARN"; "support"; "\($P) \($ck) (current)"; "\($P) standard support for the current minor 1.\($cur) ends \($cv.end_standard), within \($LOOKAHEAD) days of \($today) (dates checked \($sd.checked)). After that, \(if $provider == "eks" then "extended-support billing starts (about $\($pv.per_cluster_hour_usd.extended) vs $\($pv.per_cluster_hour_usd.standard) per cluster-hour)" else "only Extended-channel clusters stay on it (about $\($pv.per_cluster_hour_usd.extended) vs $\($pv.per_cluster_hour_usd.standard) per cluster-hour); others are auto-upgraded" end).\(pricenote($sd; $provider))"; "Finish this upgrade before \($cv.end_standard)."; $sd.sources[$provider])]
                else [] end )
          end )
    end ) as $support

# ---------- PodDisruptionBudgets ----------
# A PDB whose controller is not an apps/* object belongs to an operator (for example a CloudNativePG Cluster).
# The operator keeps it in place on purpose and is expected to move the protected role (switch over the primary)
# before a drain continues, so it is a WARN while the workload has a second instance, and a BLOCKER when it has
# only one. Either way the fix never edits or disables the operator's PDB.
| ( unchecked("poddisruptionbudgets"; $b.pdbs)
    + [ $b.pdbs | arr | .[] | . as $p | "pdb/\(.ns)/\(.name)" as $o
        | ( if (.max_unavailable != null and (.max_unavailable | pct0)) then
              {why: "maxUnavailable is \(.max_unavailable): no pod may ever be evicted, so a drain hangs.",
               fix: "Raise maxUnavailable to at least 1 (and add replicas), or agree a maintenance exception with the owner."}
            elif .min_available == "100%" then
              {why: "minAvailable is 100%: a drain can never evict these pods.",
               fix: "Lower minAvailable or add replicas so at least one disruption is allowed."}
            elif (.min_available | type) == "number" and .expected > 0 and .min_available >= .expected then
              {why: "minAvailable \(.min_available) >= the \(.expected) pods it covers: a drain can never evict them.",
               fix: "Scale the workload above \(.min_available) replicas or lower minAvailable."}
            elif .expected > 0 and .disruptions_allowed == 0 then
              {why: "Allows 0 disruptions right now (\(.healthy)/\(.expected) healthy).",
               fix: "Fix the unhealthy pods or the budget before draining."}
            else null end ) as $block
        | (.owner // null) as $own
        | if $block == null then
            (if .expected == 0 then f("INFO"; "pdb"; $o; "Selects no pods."; "Check the selector; it protects nothing."; PDB) else empty end)
          elif $own != null and (($own.api_version // "") | startswith("apps/") | not) then
            ([ $b.pods | arr | .[] | select(.ns == $p.ns and (.owner.kind // "") == $own.kind and (.owner.name // "") == $own.name) ] | length) as $pods
            | (if $pods > 0 then $pods else $p.expected end) as $inst
            | if $inst <= 1 then
                f("BLOCKER"; "pdb"; $o; "\($block.why) Managed by operator \($own.kind) \($own.name), which runs \($inst) instance in total: there is no second instance to take over, so the drain blocks.";
                  "Add a replica through the \($own.kind) resource (for example raise its instance count to 2) and wait until it has caught up, then drain. Do not edit or disable this PDB: the operator owns it."; OPPDB)
              else
                f("WARN"; "pdb"; $o; "\($block.why) Managed by operator \($own.kind) \($own.name) (\($inst) instances); the operator is expected to switch the protected role to another instance before the drain continues.";
                  "Managed by operator \($own.kind); do not edit or disable it. Confirm the database has >=2 instances and its replicas have caught up before draining each node."; OPPDB)
              end
          else f("BLOCKER"; "pdb"; $o; $block.why; $block.fix; PDB) end ] ) as $pdb

# ---------- zonal storage ----------
# A pod whose PersistentVolume is pinned to a zone can only restart on a node in that zone.
| ( unchecked("persistentvolumeclaims"; $b.pvcs) + unchecked("persistentvolumes"; $b.pvs)
    + ( if ($b.pvcs | failed) or ($b.pvs | failed) then [] else
          ( [ $b.pvs | arr | .[] | {key: .name, value: (.zones // [])} ] | from_entries ) as $pvz
          | ( [ $b.pvcs | arr | .[] | {key: "\(.ns)/\(.name)", value: .volume} ] | from_entries ) as $bound
          # Group pods that mount claims by their controller owner (StatefulSet, or an operator kind such as a
          # CloudNativePG Cluster), so operator-managed database pods are covered too.
          | [ $b.pods | arr | map(select(.owner != null and ((.claims // []) | length) > 0)) | group_by([.ns, .owner.kind, .owner.name])[]
              | .[0] as $g
              | ( [ .[] | .ns as $ns | (.claims // [])[] | ($bound["\($ns)/\(.)"] // "") | select(. != "") | ($pvz[.] // [])[] ] | unique ) as $z
              | select($z | length > 0)
              | f("WARN"; "zonal-storage"; "\($g.owner.kind | ascii_downcase)/\($g.ns)/\($g.owner.name)"; "\($g.owner.kind) \($g.owner.name): its PersistentVolumes are pinned to zone(s) \($z | join(", ")), so each pod can only restart on a node in its volume's zone.";
                  "Before draining, confirm the node pool has surge or replacement capacity in each of \($z | join(", ")) (per-zone node groups, or surge nodes that land in those zones); otherwise the pod stays Pending."; ZONE) ]
        end ) ) as $storage

# ---------- workloads that a drain disrupts ----------
| ( unchecked("deployments"; $b.deployments) + unchecked("statefulsets"; $b.statefulsets) + unchecked("pods"; $b.pods)
    + [ ($b.deployments | arr | .[] | {k: "deployment"} + .), ($b.statefulsets | arr | .[] | {k: "statefulset"} + .)
        | select(.replicas == 1)
        | f("WARN"; "single-replica"; "\(.k)/\(.ns)/\(.name)"; "Runs 1 replica: every drain of its node is an outage for it."; "Scale to 2+ with a PDB for the upgrade window, or accept and announce the blip."; DRAIN) ]
    + [ $b.pods | arr | .[] | select(.mirror | not) | select((.owner.kind // "") != "DaemonSet") | select(.phase == "Running" or .phase == "Pending")
        | if .owner == null then f("WARN"; "bare-pod"; "pod/\(.ns)/\(.name)"; "Pod has no controller: drain refuses it without --force and it is not recreated when the node is replaced."; "Move it under a Deployment/StatefulSet/Job or delete it on purpose."; DRAIN)
          else empty end ]
    + [ $b.pods | arr | .[] | select(.mirror | not) | select((.owner.kind // "") != "DaemonSet") | select(.phase == "Running")
        | select((.empty_dir | length) > 0 or (.host_path | length) > 0)
        | f("WARN"; "local-storage"; "pod/\(.ns)/\(.name)"; "Uses node-local storage (emptyDir: \(.empty_dir | join(",") | if . == "" then "-" else . end); hostPath: \(.host_path | join(",") | if . == "" then "-" else . end)); data is lost when the node drains or is replaced."; "Confirm the data is disposable, or move it to a PersistentVolume."; DRAIN) ]
  ) as $workloads

# ---------- add-ons and controllers ----------
| ( [ {re: "coredns", name: "CoreDNS"}, {re: "kube-proxy", name: "kube-proxy"},
      {re: "amazon-k8s-cni|aws-node", name: "Amazon VPC CNI"}, {re: "cilium", name: "Cilium"}, {re: "calico", name: "Calico"},
      {re: "azure-cns|azure-cni", name: "Azure CNI"}, {re: "kindnet", name: "kindnet (kind CNI)"},
      {re: "ebs-csi|aws-ebs-csi", name: "EBS CSI driver"}, {re: "efs-csi", name: "EFS CSI driver"},
      {re: "azuredisk|azurefile|blob-csi", name: "Azure CSI drivers"}, {re: "pd-csi|gcp-compute-persistent-disk", name: "GCE PD CSI driver"},
      {re: "ingress-nginx|nginx-ingress", name: "NGINX ingress controller"}, {re: "aws-load-balancer-controller", name: "AWS Load Balancer Controller"},
      {re: "cert-manager", name: "cert-manager"}, {re: "metrics-server", name: "metrics-server"},
      {re: "cluster-autoscaler", name: "Cluster Autoscaler"}, {re: "karpenter", name: "Karpenter"},
      {re: "gatekeeper", name: "OPA Gatekeeper"}, {re: "kyverno", name: "Kyverno"}, {re: "istiod|istio-proxy", name: "Istio"} ] ) as $known
| ( [ ($b.deployments | arr | .[] | {k: "deployment"} + .), ($b.daemonsets | arr | .[] | {k: "daemonset"} + .) ] ) as $all
| ( [ $known[] as $a | $all[] | . as $w | .images[] | select(test($a.re)) | {addon: $a.name, obj: "\($w.k)/\($w.ns)/\($w.name)", image: ., tag: tag} ]
    | unique_by(.obj + .image) ) as $addons
| ( [ $addons[]
      | if .addon == "Cluster Autoscaler" and (.tag | minor) != $t then f("WARN"; "addon"; .obj; "Cluster Autoscaler \(.tag) should track the cluster minor; it will be behind 1.\($t)."; "Upgrade it to the latest 1.\($t).x release right after the control plane."; "https://github.com/kubernetes/autoscaler/releases")
        elif .addon == "CoreDNS" and ($b.support.kubeadm_coredns["1.\($t)"] // "") as $bd | $bd != "" and (.tag == $bd or (.tag | startswith($bd + "-"))) then f("INFO"; "addon"; .obj; "CoreDNS \(.tag) is the version kubeadm ships with 1.\($t)."; "No action needed for this hop."; "")
        elif .addon == "kube-proxy" then f("INFO"; "addon"; .obj; "kube-proxy \(.tag) (skew checked above)."; "Upgrade with the nodes/managed add-on after the control plane."; SKEW)
        else f("WARN"; "addon"; .obj; "\(.addon) \(.tag): confirm this version supports 1.\($t) before the control-plane upgrade."; "Check the vendor compatibility matrix; upgrade first if 1.\($t) is not listed. Managed add-ons: see \($pref)."; "") end ] ) as $addon_findings

# ---------- admission webhooks ----------
| ( [ $b.services | arr | .[] | "\(.ns)/\(.name)" ] ) as $svcs
| ( [ $b.slices | arr | .[] | select(.ready > 0) | "\(.ns)/\(.service)" ] | unique ) as $ready
| ( unchecked("validatingwebhookconfigurations"; $b.vwh) + unchecked("mutatingwebhookconfigurations"; $b.mwh)
    + [ ($b.vwh | arr | .[] | {kind: "validatingwebhookconfiguration"} + .), ($b.mwh | arr | .[] | {kind: "mutatingwebhookconfiguration"} + .)
        | . as $c | .webhooks[] | . as $h | "\($c.kind)/\($c.name) (\($h.name))" as $o
        | if .service == null then f("INFO"; "webhook"; $o; "Calls an external URL; reachability not checked."; "Confirm the endpoint is up before upgrading."; HOOK)
          else "\(.service.namespace)/\(.service.name)" as $s
          | (if ($svcs | index($s)) == null then "service \($s) does not exist" elif ($ready | index($s)) == null then "service \($s) has no ready endpoints" else "" end) as $why
          | if $why == "" then empty
            elif .failure_policy == "Fail" then f("BLOCKER"; "webhook"; $o; "failurePolicy Fail and \($why): matching API writes are rejected, which can stall node replacement and add-on updates."; "Restore the backing service, or have the owner remove the webhook or set it to Ignore before the upgrade."; HOOK)
            else f("WARN"; "webhook"; $o; "failurePolicy Ignore but \($why): every matching request waits for the timeout."; "Restore or remove the webhook."; HOOK) end
          end ] ) as $webhooks
| ( unchecked("apiservices"; $b.apiservices)
    + [ $b.apiservices | arr | .[] | select(.service != null and .available != "True")
        | f("WARN"; "apiservice"; "apiservice/\(.name)"; "Aggregated API is not Available (\(.reason)): discovery is partial and namespace deletion can hang."; "Fix the backing service (often metrics-server) or remove the stale APIService."; HOOK) ] ) as $apisvc

| ( if $b.pool_label_skipped == true then [f("INFO"; "coverage"; "node pools"; "--pool-label \($b.pool_label) was not applied: the recorded nodes carry no labels (recorded before labels were captured)."; "Re-record the fixtures, or run against the cluster."; "")] else [] end ) as $poolnote
| ($skew + $poolnote + $health + $removed + $support + $pdb + $storage + $workloads + $addon_findings + $webhooks + $apisvc) as $all_findings
| {
    context: $b.ctx, generated_at: $b.now, provider: $provider,
    cluster: {server_version: $sv, current_minor: $cur, target_minor: $t,
              node_pools: ([$b.nodes | arr | .[] | {pool: (if .pool == "" then "(unlabelled)" else .pool end), kubelet}] | group_by(.pool) | map({pool: .[0].pool, nodes: length, kubelet_versions: (map(.kubelet) | unique)}))},
    removed_api_window: [ $window[] | "\(.group)/\(.version) \(.kind) (removed in 1.\(.removed_in))" ],
    addons: $addons,
    summary: { blockers: ([$all_findings[] | select(.severity == "BLOCKER")] | length),
               warnings: ([$all_findings[] | select(.severity == "WARN")] | length),
               info: ([$all_findings[] | select(.severity == "INFO")] | length) },
    verdict: (if any($all_findings[]; .severity == "BLOCKER") then "NO-GO" elif any($all_findings[]; .severity == "WARN") then "GO-WITH-WARNINGS" else "GO" end),
    findings: ($all_findings | sort_by({BLOCKER: 0, WARN: 1, INFO: 2, OK: 3}[.severity], .category, .object))
  }
