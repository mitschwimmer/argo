# Walter deployment

This directory declares Walter on the existing public Cilium Gateway at
https://walter.archaic.work. Walter's source and operational contract:
https://github.com/mitschwimmer/walter/blob/main/.agents/skills/walter/references/operations.md

## Deployment prerequisites and operations

1. **Strata API key:** The encrypted `strata-sealedsecret.yaml`
   is committed and included in the Kustomization. It creates
   `walter/walter-strata-api-key` (key `api-key`) when the current
   cluster's Sealed Secrets controller decrypts it. The sealing
   certificate is available at
   `https://seal.archaic.work/v1/cert.pem`.
   Never commit the plaintext key or an unencrypted Kubernetes Secret.
   Ensure the running Strata server accepts the sealed key. Preserve
   the controller's private sealing keys in encrypted off-cluster
   backups and test recovery.

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
