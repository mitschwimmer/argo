#!/bin/sh
set -eu
unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
gateway=https://gateway.poc.test:8443
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
test ! -e /var/run/secrets/kubernetes.io/serviceaccount/token
test -s /trust/ca.crt
curl -fsS --max-time 5 http://127.0.0.1:4096/ >"$scratch/ui"
test -s "$scratch/ui"
printf 'OpenCode served its web UI on loopback.\n'

GIT_TERMINAL_PROMPT=0 git -c credential.helper= -c protocol.version=2 \
  -c http.followRedirects=false clone --quiet "$gateway/repo.git" "$scratch/repo"
test "$(cat "$scratch/repo/README.md")" = "coding-agent-poc fixture"
printf 'Cloned the protected Git fixture via HTTPS.\n'

for header in "" "Authorization: Bearer client-supplied"; do
  response=$(curl -fsS --max-time 5 -H "$header" "$gateway/private")
  test "$response" = '{"fixture":"protected"}'
done
printf 'Protected JSON returned the expected body with missing and client-supplied authorization.\n'

assert_404() {
  local method=$1 path=$2 status
  status=$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' -X "$method" "$gateway$path")
  test "$status" = 404
}
assert_404 GET /unapproved
assert_404 POST /private
assert_404 POST /repo.git/git-receive-pack
assert_404 GET '/repo.git/info/refs?service=git-receive-pack'
printf 'Unapproved routes and Git pushes were rejected.\n'

unreachable() {
  local name=$1 url=$2 result code=0
  result=$(curl -sS --connect-timeout 2 --max-time 3 -o /dev/null -w '%{time_connect}' "$url" 2>/dev/null) || code=$?
  case "$code:$result" in
    7:0.000000|28:0.000000) printf 'No TCP connection to %s.\n' "$name" ;;
    *) printf 'Expected connection failure to %s, got curl %s with connect time %s.\n' "$name" "$code" "$result" >&2; exit 1 ;;
  esac
}
unreachable "direct upstream" "https://$1:8444/private"
unreachable "Kubernetes API" "https://$2:443/version"
unreachable "cluster DNS (TCP)" "http://$3:53/"
unreachable "gateway readiness port" "http://$4:19003/ready"
unreachable "external IP" "https://1.1.1.1:443/"
