#!/usr/bin/env bash
set -euo pipefail

poc=coding-agent-poc
envoy_namespace=${ENVOY_NAMESPACE:-envoy-gateway-system}
part_of=app.kubernetes.io/part-of
dir=$(cd -- "$(dirname -- "$0")" && pwd)
selector="gateway.envoyproxy.io/owning-gateway-namespace=$poc,gateway.envoyproxy.io/owning-gateway-name=task"

die() { printf '%s\n' "$*" >&2; exit 1; }

(( $# >= 2 )) || die "Usage: $0 {deploy|verify|cleanup} CONTEXT [IMAGE]"
action=$1
context=$2
shift 2
[[ -n "$context" && "$envoy_namespace" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || die "Invalid context or Envoy namespace."
k=(kubectl --context "$context")
ns() { "${k[@]}" -n "$poc" "$@"; }
envoy() { "${k[@]}" -n "$envoy_namespace" "$@"; }

owned() {
  local ownership
  ownership=$("${k[@]}" get "$@" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/part-of}')
  [[ "$ownership" == "$poc" ]] || die "Unexpected ownership for $*."
}

wait_route() {
  local condition
  for condition in Accepted ResolvedRefs; do
    ns wait --for="jsonpath={.status.parents[?(@.controllerName=='gateway.envoyproxy.io/gatewayclass-controller')].conditions[?(@.type=='$condition')].status}=True" \
      httproute/capabilities --timeout=90s
  done
}

certificates() {
  local p=$1 name
  openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 7 \
    -subj "/CN=coding-agent-poc CA" -keyout "$p/ca.key" -out "$p/ca.crt" >/dev/null 2>&1
  for name in gateway fixture; do
    openssl req -new -newkey rsa:2048 -nodes -subj "/CN=$name.poc.test" \
      -keyout "$p/$name.key" -out "$p/$name.csr" >/dev/null 2>&1
    printf 'subjectAltName=DNS:%s.poc.test\nextendedKeyUsage=serverAuth\n' "$name" >"$p/$name.ext"
    openssl x509 -req -in "$p/$name.csr" -CA "$p/ca.crt" -CAkey "$p/ca.key" \
      -CAcreateserial -days 7 -sha256 -extfile "$p/$name.ext" -out "$p/$name.crt" >/dev/null 2>&1
  done
}

deploy() {
  local image=$1 name gateway_ip service cilium_settings
  [[ "$image" =~ ^[a-zA-Z0-9][a-zA-Z0-9._:/@-]+$ ]] || die "Use a registry image reference."
  "${k[@]}" get runtimeclass kata-qemu-runtime-rs >/dev/null
  "${k[@]}" get crd sandboxes.agents.x-k8s.io ciliumendpoints.cilium.io \
    httproutefilters.gateway.envoyproxy.io envoyproxies.gateway.envoyproxy.io \
    backendtlspolicies.gateway.networking.k8s.io >/dev/null
  "${k[@]}" get namespace "$envoy_namespace" >/dev/null
  cilium_settings=$("${k[@]}" -n kube-system get configmap cilium-config \
    -o jsonpath='{.data.enable-policy}:{.data.kube-proxy-replacement}:{.data.bpf-lb-sock-hostns-only}')
  case "$cilium_settings" in
    never:*) die "Cilium policy enforcement is disabled." ;;
    *:true:true) ;;
    *:true:*) die "Set Cilium socketLB.hostNamespaceOnly=true for Kata with kube-proxy replacement." ;;
  esac
  # Each deploy starts with a new task namespace and new credentials.
  "${k[@]}" create -f - <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: $poc
  labels:
    $part_of: $poc
YAML
  umask 077
  scratch=$(mktemp -d)
  trap 'rm -rf -- "$scratch"' EXIT
  certificates "$scratch"
  for name in gateway fixture; do
    ns create secret tls "$name-tls" --cert="$scratch/$name.crt" --key="$scratch/$name.key"
  done
  for name in git json; do
    local token
    token=$(openssl rand -hex 32)
    printf 'Bearer %s' "$token" >"$scratch/credential"
    ns create secret generic "$name-auth" --from-file="credential=$scratch/credential"
  done
  ns create configmap poc-ca --from-file="ca.crt=$scratch/ca.crt"
  ns create configmap fixture --from-file="fixture.py=$dir/fixture.py"
  rm -rf -- "$scratch"
  trap - EXIT
  sed "s/__ENVOY_NAMESPACE__/$envoy_namespace/g" "$dir/isolation.yaml" | ns create -f -
  sed "s/__ENVOY_NAMESPACE__/$envoy_namespace/g" "$dir/gateway-ingress.yaml" | envoy create -f -
  sed "s|__IMAGE__|$image|g" "$dir/fixture.yaml" | ns create -f -
  ns rollout status deployment/fixture --timeout=180s
  ns create -f "$dir/gateway.yaml" --dry-run=server >/dev/null
  ns create -f "$dir/gateway.yaml"
  ns wait --for=condition=Programmed gateway/task --timeout=180s
  wait_route
  service=$(envoy get service -l "$selector" -o name)
  [[ "$service" =~ ^service/[a-z0-9][a-z0-9.-]*$ ]] || die "Expected exactly one task Envoy Service."
  [[ "$(envoy get "$service" -o jsonpath='{.spec.type}:{.spec.ports[0].targetPort}')" == ClusterIP:8443 ]] ||
    die "The task Envoy Service must be ClusterIP and target TCP 8443."
  envoy rollout status deployment -l "$selector" --timeout=180s
  gateway_ip=$(envoy get "$service" -o jsonpath='{.spec.clusterIP}')
  [[ "$gateway_ip" =~ ^[a-fA-F0-9:.]+$ ]] || die "Envoy Service has no ClusterIP."
  sed -e "s|__IMAGE__|$image|g" -e "s/__GATEWAY_IP__/$gateway_ip/g" "$dir/sandbox.yaml" | ns create -f -
  ns wait --for=create pod/opencode --timeout=90s
  ns wait --for=condition=Ready pod/opencode --timeout=180s
}

verify() {
  local fixture_ip api_ip dns_ip envoy_ip
  owned namespace "$poc"
  wait_route
  fixture_ip=$(ns get service fixture -o jsonpath='{.spec.clusterIP}')
  api_ip=$("${k[@]}" -n default get service kubernetes -o jsonpath='{.spec.clusterIP}')
  dns_ip=$("${k[@]}" -n kube-system get service kube-dns -o jsonpath='{.spec.clusterIP}')
  envoy_ip=$(envoy get pod -l "$selector" -o jsonpath='{.items[0].status.podIP}')
  [[ -n "$fixture_ip" && -n "$api_ip" && -n "$dns_ip" && -n "$envoy_ip" ]] || die "Missing probe targets."
  [[ "$(ns get pod/opencode -o jsonpath='{.spec.runtimeClassName}:{.spec.automountServiceAccountToken}')" == kata-qemu-runtime-rs:false ]] ||
    die "Unexpected Sandbox runtime or service-account configuration."
  [[ "$(ns get pod/opencode -o jsonpath='{.spec.volumes[*].name}')" == "workspace tmp ca" ]] ||
    die "Unexpected volumes in the Sandbox Pod."
  ns get ciliumendpoint opencode -o name
  ns exec -i pod/opencode -- sh -s -- "$fixture_ip" "$api_ip" "$dns_ip" "$envoy_ip" <"$dir/verify.sh"
}

cleanup() {
  if [[ -n "$("${k[@]}" get namespace "$poc" --ignore-not-found -o name)" ]]; then
    owned namespace "$poc"
    ns delete gateway task --ignore-not-found --timeout=120s
    ns delete namespace "$poc" --timeout=120s
  fi
  if [[ -n "$(envoy get service,deployment -l "$selector" -o name)" ]]; then
    envoy wait --for=delete service,deployment -l "$selector" --timeout=120s
  fi
  for resource in gatewayclass/"$poc" cnp/"$poc"-gateway; do
    if [[ -n "$(envoy get "$resource" --ignore-not-found -o name)" ]]; then
      owned "$resource" -n "$envoy_namespace"
      envoy delete "$resource" --timeout=120s
    fi
  done
  [[ -z "$(envoy get service,deployment -l "$selector" -o name)" ]] ||
    die "Task proxy still exists. Check the Envoy Gateway controller's reconciliation."
}

case "$action" in
  deploy) (( $# == 1 )) || die "deploy requires IMAGE."; deploy "$1" ;;
  verify) (( $# == 0 )) || die "verify takes only CONTEXT."; verify ;;
  cleanup) (( $# == 0 )) || die "cleanup takes only CONTEXT."; cleanup ;;
  *) die "Unknown action $action." ;;
esac
