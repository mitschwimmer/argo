#!/usr/bin/env bash
# Re-seal an existing Strata API key for the walter-develop namespace.
# Requires kubectl, kubeseal, curl and base64 on a trusted workstation.
set -euo pipefail
set +x

cd "$(dirname "$0")"
output="strata-sealedsecret.yaml"
if [[ -e "$output" ]]; then
  echo "Refusing to overwrite $output. Remove it intentionally to re-seal." >&2
  exit 1
fi
for cmd in kubectl kubeseal curl base64; do
  command -v "$cmd" >/dev/null || { echo "Missing tool: $cmd" >&2; exit 1; }
done

cert="$(mktemp)"
trap 'rm -f "$cert"' EXIT
curl --fail --silent --show-error --location \
  https://seal.archaic.work/v1/cert.pem --output "$cert"

# Plaintext is carried only via a pipe, never written to disk or printed.
# The captured shell variable holds only ciphertext.
sealed="$(
  kubectl -n walter get secret walter-strata-api-key -o jsonpath='{.data.api-key}' |
    base64 --decode |
    kubeseal --raw --scope strict --cert "$cert" \
      --namespace walter-develop --name walter-strata-api-key
)"
if [[ -z "$sealed" ]]; then
  echo "No ciphertext returned; refusing to write a manifest." >&2
  exit 1
fi
cat > "$output" <<EOF
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: walter-strata-api-key
  namespace: walter-develop
spec:
  encryptedData:
    api-key: ${sealed}
  template:
    metadata:
      name: walter-strata-api-key
      namespace: walter-develop
EOF
echo "Wrote $output (ciphertext only). Add it to kustomization.yaml and commit."
