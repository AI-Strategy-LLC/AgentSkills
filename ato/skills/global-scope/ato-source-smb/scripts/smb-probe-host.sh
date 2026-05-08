#!/usr/bin/env bash
# smb-probe-host.sh — Parse a UNC/URL location and probe the host without auth.
#
# Best-effort, ambient. Used by the ato-source-smb skill in Step 2 (VALIDATE)
# to fail fast on typo'd hostnames or unreachable shares before invoking
# mount_smbfs / mount.cifs / Windows UNC access.
#
# Inputs (one positional argument):
#   smb://hostname/share[/path]      URL form
#   //hostname/share[/path]          POSIX-UNC form
#   \\hostname\share[\path]          Windows-UNC form (backslash-separated)
#
# Outputs JSON to stdout, e.g.:
#   {
#     "input": "smb://fileserver.corp/ato/Current",
#     "host": "fileserver.corp",
#     "share": "ato",
#     "path": "Current",
#     "scheme": "smb",
#     "normalized_unc": "//fileserver.corp/ato/Current",
#     "resolves": "true",
#     "resolves_via": "getent",
#     "port_445": "open",
#     "port_445_via": "nc"
#   }
#
# Exit codes:
#   0  ok — both probes passed or were skipped (no resolver / no prober)
#   1  DNS clearly failed (host did not resolve)
#   2  TCP probe clearly failed (port 445 closed / host unreachable)
#   64 usage error

set -u

usage() {
  cat >&2 <<'EOF'
Usage: smb-probe-host.sh <location>

  <location> ∈ {
    smb://hostname/share[/path]
    //hostname/share[/path]
    \\hostname\share[\path]
  }

EOF
}

# ---------- 1. parse ----------

[ $# -eq 1 ] || { usage; exit 64; }
INPUT="$1"
[ -n "$INPUT" ] || { usage; exit 64; }

# Convert any backslashes to forward slashes (handles \\host\share)
norm="${INPUT//\\//}"

# Strip "smb:" scheme if present
scheme=""
if [ "${norm#smb:}" != "$norm" ]; then
  scheme="smb"
  norm="${norm#smb:}"
fi

# Expect leading //
case "$norm" in
  //*) : ;;
  *)
    echo "Location must start with //, \\\\, or smb:// — got: $INPUT" >&2
    exit 64
    ;;
esac
norm="${norm#//}"

# host [ / share [ / path ] ]
host="${norm%%/*}"
rest="${norm#"$host"}"
rest="${rest#/}"
share="${rest%%/*}"
path="${rest#"$share"}"
path="${path#/}"

[ -n "$host" ] || { echo "Could not parse host from: $INPUT" >&2; exit 64; }

normalized_unc="//${host}"
[ -n "$share" ] && normalized_unc="${normalized_unc}/${share}"
[ -n "$path" ]  && normalized_unc="${normalized_unc}/${path}"

# ---------- 2. DNS probe (best-effort) ----------

resolves="unknown"
resolves_via=""

if command -v getent >/dev/null 2>&1; then
  if getent hosts "$host" >/dev/null 2>&1; then
    resolves="true"; else resolves="false"; fi
  resolves_via="getent"
elif command -v dscacheutil >/dev/null 2>&1; then
  # macOS — dscacheutil prints "ip_address: ..." lines on success
  if dscacheutil -q host -a name "$host" 2>/dev/null | grep -qi '^ip'; then
    resolves="true"; else resolves="false"; fi
  resolves_via="dscacheutil"
elif command -v host >/dev/null 2>&1; then
  if host -W 2 "$host" >/dev/null 2>&1; then
    resolves="true"; else resolves="false"; fi
  resolves_via="host"
elif command -v dig >/dev/null 2>&1; then
  if [ -n "$(dig +short +time=2 +tries=1 "$host" 2>/dev/null)" ]; then
    resolves="true"; else resolves="false"; fi
  resolves_via="dig"
elif command -v nslookup >/dev/null 2>&1; then
  if nslookup "$host" >/dev/null 2>&1; then
    resolves="true"; else resolves="false"; fi
  resolves_via="nslookup"
elif command -v python3 >/dev/null 2>&1; then
  if python3 -c "import socket,sys; socket.gethostbyname(sys.argv[1])" "$host" \
       >/dev/null 2>&1; then
    resolves="true"; else resolves="false"; fi
  resolves_via="python3"
else
  resolves="skipped"
  resolves_via="no_resolver"
fi

# ---------- 3. TCP probe to port 445 (best-effort) ----------

port_445="unknown"
port_445_via=""

probe_via_nc() {
  # BSD nc (macOS preinstalled) uses -G for connect-timeout.
  # GNU nc uses -w for both connect and idle timeout.
  # Try BSD style first; fall back to GNU style.
  nc -z -G 2 "$host" 445 >/dev/null 2>&1 && return 0
  nc -z -w 2 "$host" 445 >/dev/null 2>&1 && return 0
  return 1
}

probe_via_bash_tcp() {
  # Bash /dev/tcp pseudo-device + a 2s timeout from coreutils (timeout / gtimeout)
  local timeout_cmd=""
  if   command -v timeout  >/dev/null 2>&1; then timeout_cmd="timeout"
  elif command -v gtimeout >/dev/null 2>&1; then timeout_cmd="gtimeout"
  else return 99
  fi
  "$timeout_cmd" 2 bash -c "exec 3<>/dev/tcp/$host/445" 2>/dev/null
}

if command -v nc >/dev/null 2>&1; then
  if probe_via_nc; then port_445="open"; else port_445="closed"; fi
  port_445_via="nc"
else
  probe_via_bash_tcp; rc=$?
  if   [ "$rc" = "0" ]; then port_445="open";  port_445_via="bash-tcp"
  elif [ "$rc" = "99" ]; then port_445="skipped"; port_445_via="no_prober"
  else port_445="closed"; port_445_via="bash-tcp"
  fi
fi

# ---------- 4. emit JSON ----------

if command -v jq >/dev/null 2>&1; then
  jq -n \
    --arg input "$INPUT" \
    --arg host "$host" \
    --arg share "$share" \
    --arg path "$path" \
    --arg scheme "$scheme" \
    --arg unc "$normalized_unc" \
    --arg resolves "$resolves" \
    --arg resolves_via "$resolves_via" \
    --arg port_445 "$port_445" \
    --arg port_445_via "$port_445_via" \
    '{input:$input, host:$host, share:$share, path:$path, scheme:$scheme,
      normalized_unc:$unc, resolves:$resolves, resolves_via:$resolves_via,
      port_445:$port_445, port_445_via:$port_445_via}'
else
  # jq missing — hand-roll. Hostnames + share names are restricted to a
  # safe character set, so we don't escape further.
  printf '{"input":"%s","host":"%s","share":"%s","path":"%s","scheme":"%s","normalized_unc":"%s","resolves":"%s","resolves_via":"%s","port_445":"%s","port_445_via":"%s"}\n' \
    "$INPUT" "$host" "$share" "$path" "$scheme" "$normalized_unc" \
    "$resolves" "$resolves_via" "$port_445" "$port_445_via"
fi

# ---------- 5. exit code ----------

if [ "$resolves" = "false" ]; then
  exit 1
elif [ "$port_445" = "closed" ]; then
  exit 2
else
  exit 0
fi
