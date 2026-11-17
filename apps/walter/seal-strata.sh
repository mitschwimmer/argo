#!/usr/bin/env bash
# Re-encrypt existing walter/walter-strata-api-key for both new namespaces.
# Run with kubectl access while the old walter namespace still exists.
set -euo pipefail
set +x
umask 077
cd "$(dirname "$0")"

for env in prd dev; do
  if [[ -e "$env/strata-sealedsecret.yaml" ]]; then
    echo "Refusing to overwrite $env/strata-sealedsecret.yaml" >&2
    exit 1
  fi
done
for cmd in kubectl kubeseal curl base64; do
  command -v "$cmd" >/dev/null || { echo "Missing tool: $cmd" >&2; exit 1; }
done

cert="$(mktemp)"
trap 'rm -f "$cert"' EXIT
curl --fail --silent --show-error --location \
  https://seal.lan.archaic.work/v1/cert.pem --output "$cert"

for env in prd dev; do
  # Never print the old key or write it to a file. The variable below
  # captures only ciphertext; each seal has a different strict namespace.
  sealed="$(
    kubectl -n walter get secret walter-strata-api-key -o jsonpath='{.data.api-key}' |
      base64 --decode |
      kubeseal --raw --scope strict --cert "$cert" \
        --namespace "walter-$env" --name walter-strata-api-key
  )"
  if [[ -z "$sealed" ]]; then
    echo "No ciphertext returned for walter-$env" >&2
    exit 1
  fi
  cat > "$env/strata-sealedsecret.yaml" <<EOF
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: walter-strata-api-key
  namespace: walter-$env
  labels:
    environment: $env
spec:
  encryptedData:
    api-key: ${sealed}
  template:
    metadata:
      name: walter-strata-api-key
      namespace: walter-$env
      labels:
        environment: $env
EOF
  echo "Wrote $env/strata-sealedsecret.yaml (ciphertext only)"
done
echo "Add each strata-sealedsecret.yaml to its namespace's kustomization.yaml."
