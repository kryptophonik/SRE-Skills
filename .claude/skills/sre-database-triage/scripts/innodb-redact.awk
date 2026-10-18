# innodb-redact.awk: BEST-EFFORT, defence-in-depth redaction of statement text in SHOW ENGINE INNODB
# STATUS output, for interactive use only. It is NOT a guarantee: the output can still contain passwords
# and row values, so never paste it into tickets, chat or the evidence bundle (db-snapshot.sh does not
# capture INNODB STATUS at all). Used by db-ro.sh for every mysql/mariadb "SHOW ENGINE ..." statement.
# mysql --batch prints the status as ONE row with newlines escaped as the two characters \n (and a
# backslash as \\); interactive/--raw output has real newlines. Both are handled: the text is cut into
# pieces at real and escaped newlines, and state carries across pieces.
# A piece whose upper-case form contains PASSWORD or IDENTIFIED is replaced by a marker, and so is every
# following piece until the next GENUINE monitor marker (---TRANSACTION, ------- TRX HAS BEEN WAITING,
# *** (n) / *** WE ROLL BACK, RECORD LOCKS space id, TABLE LOCK table, Trx read view, MySQL/MariaDB thread
# id, ====, a run of 8+ dashes, END OF INNODB). Bare "---x", "*** x" or "---" lines inside statement text
# do not reset it (Database Reviewer round 3, tightened structural()).
# Known limitation: a statement can contain any bytes, including an exact copy of a genuine marker
# (e.g. a line "---TRANSACTION 999" or 8+ dashes) between the keyword and the secret; redaction then ends
# early and the secret is printed. No line filter over free-form SQL can close that.
# Portability: POSIX awk only, tested with gawk, mawk, BWK awk (macOS awk) and busybox awk. No regular
# expressions on backslashes and no data in printf formats: those are where awks differ.
BEGIN { BS = "\\"; ESC_NL = BS "n"; ESC_BS = BS BS; HOLD = "\001"
        MARK = "<redacted: may contain a password>"; red = 0 }
function rep(s, a, b,   o, i) { o = ""; while ((i = index(s, a)) > 0) { o = o substr(s, 1, i - 1) b; s = substr(s, i + length(a)) } return o s }
function starts(p, pre) { return substr(p, 1, length(pre)) == pre }
function onlydashes(p,   i, c) { if (length(p) < 8) return 0; for (i = 1; i <= length(p); i++) { c = substr(p, i, 1); if (c != "-") return 0 } return 1 }
function structural(p) {
  # Only GENUINE monitor markers reset redaction (see the header for the residual limitation).
  return starts(p, "---TRANSACTION ") || starts(p, "------- TRX HAS BEEN WAITING") ||
         starts(p, "*** (") || starts(p, "*** WE ROLL BACK") ||
         starts(p, "TABLE LOCK table ") || starts(p, "RECORD LOCKS space id ") ||
         starts(p, "Trx read view ") || starts(p, "MySQL thread id ") ||
         starts(p, "MariaDB thread id ") || starts(p, "END OF INNODB") ||
         starts(p, "====") || onlydashes(p)
}
function fix(p,   u, q) {
  q = p; sub(/^[ \t]+/, "", q)            # tab-separated batch row: the status column follows "InnoDB<TAB><TAB>"
  if (structural(q)) red = 0
  u = toupper(p)
  if (index(u, "PASSWORD") > 0 || index(u, "IDENTIFIED") > 0) red = 1
  if (red) { nred++; return MARK }
  return p
}
{
  s = rep($0, ESC_BS, HOLD); out = ""
  while ((i = index(s, ESC_NL)) > 0) { out = out fix(substr(s, 1, i - 1)) ESC_NL; s = substr(s, i + 2) }
  out = out fix(s)
  printf "%s\n", rep(out, HOLD, ESC_BS)
}
END { if (nred > 0) printf "[db-ro: %d INNODB STATUS piece(s) redacted: may contain a password]\n", nred
      # Always shown, redaction or not: the filter is best-effort.
      printf "[db-ro: best-effort redaction only; output may still contain passwords and row values: do not paste it anywhere]\n" }
