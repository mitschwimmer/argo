# Walter deployment

This directory declares Walter on the existing public Cilium Gateway at
https://walter.archaic.work. Walter's source and operational contract:
https://github.com/mitschwimmer/walter/blob/main/.agents/skills/walter/references/operations.md

## Before merging this draft PR

1. **Strata API key:** Seal a dedicated key using the **current cluster's**
   Sealed Secrets public certificate. The repository is public; never commit
   a plaintext Secret, key, credentials file or unencrypted pipeline log.

   On a K3s server with kubeseal installed, you can fetch the public
   certificate (adapt KUBECONFIG for your environment):

   ```sh
   sudo env KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubeseal \
     --controller-name sealed-secrets-controller \
     --controller-namespace sealed-secrets --fetch-cert > sealed-secrets.pem
   ```

   From an argo checkout with k3s kubectl and a key file readable only by you:

   ```sh
   k3s kubectl -n walter create secret generic walter-strata-api-key \
     --from-file=api-key=/secure/path/to/strata-api-key \
     --dry-run=client -o yaml | \
     kubeseal --cert sealed-secrets.pem --format yaml \
     > apps/walter/strata-sealedsecret.yaml
   ```

   Check the resulting SealedSecret is named `walter-strata-api-key` in
   namespace `walter`, with an encrypted `api-key`. Add
   `strata-sealedsecret.yaml` to the resources in
   `apps/walter/kustomization.yaml` and commit it to the PR. Use the
   exact same Secret name and namespace when resealing. Avoid keeping the
   private key file on shared hosts.

2. **DNS:** Point the public A record for `walter.archaic.work` to the
   same external address used for `auth.archaic.work`. The existing
   router forwards ports 80/443 to Cilium's Gateway at `192.168.1.201`.
   Check that cert-manager issues `walter-archaic-work-tls` in `edge`.

3. **GHCR:** Verify nodes can pull
   `ghcr.io/mitschwimmer/walter@sha256:9b68b135f08919e816a1476e88b83af57ea5ae87cf47ca78dd2cbbc1a254f407`.
   This digest comes from successful main-branch run
   https://github.com/mitschwimmer/walter/actions/runs/40758951586
   (source revision `da97300c727e0bf1610365079a644152b8e0ed2b`).
   The image is built only for linux/amd64.

4. **Strata:** The NixOS `meablack` host is `192.168.1.28` and its
   firewall allows TCP 8080. Walter's Strata example documents
   `/v1/chat/completions` and model `qwen3.8-flash-next-iq3_s`.
   Confirm the **running** Strata service actually listens on
   `192.168.1.28:8080` and that the supplied key is valid. The endpoint
   uses plain HTTP over the LAN, so prompts and bearer keys are not
   encrypted in transit. Prefer a trusted/private network path or HTTPS.

5. **Kanidm account:** Kaniop creates `KanidmPersonAccount/henner` and
   `KanidmGroup/walter-users` in namespace `kanidm`, and the confidential
   `KanidmOAuth2Client/walter` in namespace `walter`. No OIDC secret needs
   manual sealing: Kaniop creates the namespaced Secret
   `walter-kanidm-oauth2-credentials` with key `CLIENT_SECRET`.
   Inspect the person resource's Kubernetes Events for the initial
   credential-setup URL. Treat it as a short-lived sensitive token and
   never commit or share it in logs. The group claim is explicitly mapped
   to `groups: ["walter-users"]`.

6. **Backups:** The 10Gi OpenEBS hostpath PVC is node-local and is not a
   backup. Before storing private conversations, establish encrypted,
   off-cluster backups, verify restoration, and preserve the UID/GID
   65532 ownership requirement. Only one writer should own `/data`.

## Verification after deployment

```sh
k3s kubectl -n argocd get applications kanidm walter public-gateway
k3s kubectl -n kanidm get kanidmpersonaccounts,kanidmgroups
k3s kubectl -n walter get kanidmoauth2clients,secrets,pvc,pods,svc,httproutes
k3s kubectl -n edge get gateway public
k3s kubectl -n walter get endpointslices -l kubernetes.io/service-name=walter
```

Check OIDC client readiness, successful sign-in to
`https://walter.archaic.work` for `henner`, rejection for
nonmembers, SSE streaming, logout, restarts and persisted conversations.
If login fails, verify the discovery issuer at
`https://auth.archaic.work/oauth2/openid/walter/.well-known/openid-configuration`.

The Deployment intentionally cannot become ready until both Kaniop's
generated OIDC Secret and the sealed Strata API key Secret exist. Do not
merge this draft without adding the encrypted Secret and verifying DNS.
