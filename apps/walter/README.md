# Walter environments

The `prd` and `dev` overlays deploy **the same Kubernetes resource names**
into separate namespaces:

| | Production | Development |
|---|---|---|
| Namespace | `walter-prd` | `walter-dev` |
| HTTPS origin | `https://walter.archaic.work` | `https://walter-dev.archaic.work` |
| Deployment/Service/HTTPRoute | `walter` | `walter` |
| PVC | `walter-data` | `walter-data` |
| KanidmOAuth2Client | `walter` | `walter` |
| Strata SealedSecret | `walter-strata-api-key` | `walter-strata-api-key` |
| Kaniop credentials Secret | `walter-kanidm-oauth2-credentials` | `walter-kanidm-oauth2-credentials` |
| Environment label | `environment: prd` | `environment: dev` |
| External Kanidm ID | `walter-prd` | `walter-dev` |

The Kubernetes object names stay constant. External Kanidm client IDs **must**
differ so the two separate OAuth2 clients do not compete for a single
identity provider object. `spec.kanidmName` distinguishes those external
IDs while both CRs have `metadata.name: walter`. Accordingly, each
Deployment's OIDC client ID and issuer use `walter-prd` / `walter-dev`.
The Kaniop-generated credentials Secret is namespaced and retains the same
Kubernetes name in each environment.

Application and AppProject names include the environment because both
live in the same `argocd` namespace. They are **not** workload resources
in `walter-prd` or `walter-dev`.

Both environments reuse the Strata inference backend and initially the
same bearer key, but each must have its own **strict-scope encrypted**
SealedSecret in its namespace. They have separate, fresh PVCs. You have
explicitly chosen to discard old conversations; **no data migration**
or backup of the original `walter/walter-data` is required.

## Required before merging

1. Publish the development image: run
   https://github.com/mitschwimmer/walter/actions/workflows/oci.yml
   on branch `develop`. Verify the published image comes from commit
   `6a0fcf13fd92050430637cf62538d21a881a23c2` and is pullable.
   The development manifest currently pins its SHA tag; prefer replacing
   it with the verified digest. Pushing to `develop` does not
   automatically publish an image.
2. **Before deleting the existing `walter` namespace**, from a checkout of
   this PR on a trusted workstation with access to the existing Kubernetes
   Secret and `kubeseal`, run:

   ```sh
   bash apps/walter/seal-strata.sh
   ```

   The helper reads the old `walter/walter-strata-api-key`, pipes the
   decrypted value into `kubeseal --raw` (never to disk), and writes
   two distinct namespace-bound encrypted SealedSecrets:
   `apps/walter/prd/strata-sealedsecret.yaml` and
   `apps/walter/dev/strata-sealedsecret.yaml`.
   Inspect both ciphertext manifests, add `  - strata-sealedsecret.yaml`
   to **both** Kustomizations and commit them. Do not copy the original
   ciphertext from the `walter` namespace or commit a plaintext Secret.
   A dedicated Strata key per environment is preferable if available.
   Both Pods require their local decrypted Secret at startup.
3. Add DNS for `walter-dev.archaic.work` to the same public address
   as `walter.archaic.work`. Check the Gateway's corresponding
   `edge/walter-dev-archaic-work-tls` certificate after sync.
4. Validate the entire change using `kubectl kustomize`:

   ```sh
   kubectl kustomize apps/walter/prd
   kubectl kustomize apps/walter/dev
   kubectl kustomize clusters/homelab
   ```

**Keep the PR draft; do not merge until the encrypted Secrets, image, and
DNS prerequisites are satisfied.** Both new Argo CD Applications initially
have automated sync disabled to prevent accidental production route
conflicts with the old `walter` Application.

## Cutover (intentional production downtime; old data discarded)

The existing `walter` Application and AppProject are not automatically
removed from the cluster. The root has `prune: false`, and the existing
Application also has `prune: false`. Merely deleting their manifests
does not remove the live resources; they would otherwise continue to
reconcile the old `walter` namespace and produce competing HTTPRoutes.

After **merging** the complete PR, and verifying `walter-prd` and
`walter-dev` Applications exist but are *not synced*:

1. Delete the old Application: `k3s kubectl -n argocd delete application walter`.
   Its manifest has no cascading-delete finalizer, so its old resources may
   remain until you remove the old namespace in the next step.
2. Delete the old namespace with its old Deployment, volume and OIDC
   client: `k3s kubectl delete namespace walter`. This **permanently
   deletes `walter/walter-data`** (OpenEBS hostpath Delete reclaim policy),
   the old Strata and OIDC Secrets, and old conversations.
   Wait until `walter` is gone and its HTTPRoute no longer attaches to
   the public Gateway. If namespace deletion hangs, inspect finalizers
   and Kaniop's CR cleanup rather than force-removing them.
3. Delete the leftover AppProject: `k3s kubectl -n argocd delete appproject walter`.
   The old root will not recreate it once merged, but pruning is disabled.
4. Manually sync `walter-prd`, then `walter-dev` through Argo CD,
   check Kaniop-generated OIDC Secrets, decrypted Strata Secrets,
   HTTPRoute acceptance, TLS, sign-in and SSE generation. Both volumes
   start empty. Verify `https://walter.archaic.work` after the cutover.
5. In a separate small GitOps change, re-enable automated sync (with
   pruning disabled) after both are healthy. This prevents accidental
   cutover before the old route and app are removed.

These are manual cluster operations, **not** performed by the PR.

## Verification

```sh
k3s kubectl -n argocd get applications walter-prd walter-dev
k3s kubectl get namespaces walter-prd walter-dev --show-labels
k3s kubectl -n walter-prd get deployments,pods,svc,pvc,httproutes,kanidmoauth2clients,sealedsecrets
k3s kubectl -n walter-dev get deployments,pods,svc,pvc,httproutes,kanidmoauth2clients,sealedsecrets
k3s kubectl -n walter-prd rollout status deployment/walter --timeout=300s
k3s kubectl -n walter-dev rollout status deployment/walter --timeout=300s
k3s kubectl -n edge get gateway public
```

Both clients use the existing `walter-users` group mapping. Check the
`groups` ID-token claim and allowed-group settings if login is rejected.
The two environments share the inference service; namespace separation
does not provide network isolation.

## Future updates

Production remains pinned to its established image digest. To test a newer
`develop` commit, manually run the Walter OCI workflow for it, pin the
resulting image digest in `apps/walter/dev/deployment.yaml`, and merge a
GitOps update. Advancing the source branch alone does not deploy it.
