# OpenCode on the LAN

OpenCode Web runs in Kata and uses Walter's Strata model `qwen3.8-flash-next-iq3_s`. The browser route attaches to the HTTPS listener on `edge/lan`. OpenCode uses its built-in server password for this test. The workspace and session data are ephemeral.

Cilium only allows OpenCode to initiate connections to the internal Strata proxy. The proxy loads the bearer token from its own Secret and only forwards chat completions to `192.168.1.28:8080`, the same HTTP upstream Walter uses. The Kata pod has no token mount, Kubernetes credentials, or DNS egress.

## Seal the Strata token

Walter's strict SealedSecret is bound to its name and namespace. To reuse the token, reseal it for `opencode/opencode-strata`. From the repo root, run this in Bash with the homelab Kubernetes context and permission to read the Walter production Secret. The token passes through stdin and only the sealed YAML is written.

```bash
set -o pipefail
sealing_cert=$(mktemp)
kubeseal --controller-name sealed-secrets-controller \
  --controller-namespace sealed-secrets --fetch-cert > "$sealing_cert" &&
sealed_yaml=$(
  kubectl -n walter-prd get secret walter-strata-api-key -o jsonpath='{.data.api-key}' |
    base64 --decode |
    kubectl -n opencode create secret generic opencode-strata \
      --from-file=api-key=/dev/stdin --dry-run=client -o yaml |
    kubeseal --cert "$sealing_cert" --scope strict --format yaml
) && printf '%s\n' "$sealed_yaml" > apps/opencode/strata-sealedsecret.yaml
rm -f "$sealing_cert"
```

If you have a new Strata token, use `IFS= read -rs strata_key` and `printf '%s' "$strata_key"` as the token input to the same `kubectl create secret` command. Unset `strata_key` after sealing. If you use the [LAN sealing certificate](../sealing-certificate/README.md), verify its fingerprint first.

Add `strata-sealedsecret.yaml` to the app's `resources` in [kustomization.yaml](kustomization.yaml), then commit the encrypted YAML and the kustomization change. Without the Secret, Kubernetes cannot start the Strata proxy.

## Try it

1. Add the local UniFi DNS record `agent.lan.archaic.work -> 192.168.1.202`. Follow the [LAN gateway runbook](../lan-gateway/README.md#split-horizon-dns-via-unifi) for DNS and WAN routing.
2. After merge and Argo sync, check that Kata is available and the Cilium rollout has finished. Changing `socketLB.hostNamespaceOnly` rolls the Cilium pods and allows the Kata guest to use the Strata ClusterIP through the veth datapath.
3. Read the generated OpenCode server password from `kubectl -n opencode logs deployment/opencode`. Open [agent.lan.archaic.work](https://agent.lan.archaic.work), choose the password sign-in option, and send a prompt to the configured Strata model. The username is `opencode` if prompted.
