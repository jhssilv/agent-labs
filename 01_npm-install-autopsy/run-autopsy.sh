#!/usr/bin/env bash
# Autopsy of a single `npm install`, at the system-call level.
#
# Runs one clean install under strace and reports what the machine did:
# processes started, files opened, and real TCP connections made.
#
# Companion to:
#   https://josehenrique.dev/posts/npm-install-syscall-autopsy/
#
# Needs: strace, node, npm.  (The Containerfile installs them.)

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
command -v strace >/dev/null || { echo "Please install strace first."; exit 1; }

work=$(mktemp -d)
trap 'echo; echo "trace and project left in: $work"' EXIT
cp "$here/package.json" "$work/"
cd "$work"

echo "# clean install under strace, in $work"
# -yy tags every file descriptor with its path or socket, so a real TCP
# connection can be told apart from the UDP probes getaddrinfo makes.
HOME="$work/home" npm_config_cache="$work/cache" \
  strace -f -yy -e trace=execve,clone,clone3,fork,vfork,connect,openat \
  -o autopsy.log -- npm install >/dev/null 2>npm.err \
  || { echo "npm install failed:"; tail -n5 npm.err; exit 1; }
log=autopsy.log

# --- processes ---------------------------------------------------------------
# A process is a clone/fork WITHOUT the CLONE_THREAD flag; with it, it is a
# thread. We anchor to "<pid> clone(" at the start of the line so a file path
# like core-js's web.structured-clone.js does not get counted, and so the
# "<... clone resumed>" halves do not count twice. npm itself is not born from a
# clone here (strace exec'd it), so this counts the children; add 1 for npm.
children=$(grep -E '^[0-9]+ +(clone3?|v?fork)\(' "$log" | grep -vc CLONE_THREAD)
threads=$(grep -E '^[0-9]+ +clone3?\(' "$log" | grep -c CLONE_THREAD)
programs=$(grep -E '^[0-9]+ +execve\(' "$log" | grep -c '= 0$')

echo
echo "processes: $((children + 1))   (npm + $children child)"
echo "threads:   $threads"
echo "programs:  $programs"
grep 'execve(' "$log" | grep '= 0$' | grep -oE 'execve\("[^"]+"' \
  | sed -E 's/.*"([^"]+)".*/\1/; s#.*/##' | sort | uniq -c | sort -rn | sed 's/^/  /'

# --- files -------------------------------------------------------------------
# A successful openat ends in "= <fd>" (with -yy the fd carries its path). A
# failed one ends in "= -1 <errno>", so skipping those drops every error, not
# just ENOENT.
files=$(grep 'openat' "$log" | grep -Ec '= [0-9]+(<|$)')
in_modules=$(grep -oE 'openat\([^,]+, "[^"]*node_modules[^"]*"' "$log" | wc -l)

echo
echo "files opened: $files   ($in_modules of them in node_modules)"

# --- network -----------------------------------------------------------------
# connect() is not the same as a connection. glibc's getaddrinfo connects UDP
# sockets to each candidate address just to sort them (RFC 6724) and sends
# nothing; the DNS resolver connects UDP to the nameserver too. Real traffic
# here is TCP on 443, so we count only that.
conns=$(grep 'connect(' "$log" | grep '<TCP' | grep -c 'htons(443)')
ips=$(grep 'connect(' "$log" | grep '<TCP' | grep 'htons(443)' \
  | grep -oE '"[0-9a-fA-F:.]+"' | sort -u | wc -l)
probes=$(grep 'connect(' "$log" | grep '<UDP' | grep -c 'htons(0)')

echo
echo "TCP connections on port 443: $conns   (to $ips IP address(es))"
echo "UDP address-sorting probes (not traffic): $probes"

scripts=$(grep 'execve(' "$log" | grep '"sh", "-c"' | grep -vc 'ENOENT')

# --- summary -----------------------------------------------------------------
echo
echo "===================== SUMMARY ====================="
echo "One 'npm install' of express + core-js became:"
echo "  * $((children + 1)) processes  ($threads threads)"
echo "  * $files files opened"
echo "  * $conns TCP connections on port 443, to $ips IP address(es)"
echo "  * $scripts install script from a dependency (its own code, run by npm)"
echo
echo "At this level you see IP addresses, not hostnames: naming the host"
echo "(registry.npmjs.org) needs the DNS or TLS side, not connect() alone."
