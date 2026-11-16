# Walter develop test instance

The second Walter instance at https://walter-develop.archaic.work tests the
`develop` branch of https://github.com/mitschwimmer/walter.
Production remains at https://walter.archaic.work.

This instance runs in its **own Kubernetes namespace `walter-develop`**.
Its Deployment, Service, PVC, HTTPRoute, confidential Kanidm OIDC client
and generated OIDC Secret are separate from production. Its namespace opts
into the existing Cilium Gateway using `gateway-access: public`, and the
existing Kanidm cross-namespace OIDC client selector using
`kaniop-identity: walter`. No production workload settings are changed.

Both instances still use the same Strata inference endpoint and, initially,
the same bearer key. Namespace separation does not provide network isolation
or independent Strata credentials; use a distinct Strata key if required.

## Before merging into main

1. **Publish the image.** In
   https://github.com/mitschwimmer/walter/actions/workflows/oci.yml choose
   **Run workflow** on `develop`. Confirm the successful run is for source
   commit `6a0fcf13fd92050430637cf62538d21a881a23c2` and that the image
   `ghcr.io/mitschwimmer/walter:sha-6a0fcf13fd92050430637cf62538d21a881a23c2`
   was published. Prefer replacing the tag in `deployment.yaml` with the
   run's immutable digest. Pushes to `develop` do not automatically publish.

2. **Re-seal the Strata key for `walter-develop`.** Strict-scope SealedSecret
   ciphertext is bound to resource name AND namespace. Copying the ciphertext
   from `apps/walter/strata-sealedsecret.yaml` will not work.
   With a trusted `kubectl` context for the homelab, `kubeseal` and `curl`
   installed, run in a checkout of this PR branch:

   ```sh
   bash apps/walter-develop/seal-strata.sh
   ```

   This reads the `walter/walter-strata-api-key` Secret, keeps the plaintext
   in a pipe, uses the controller's published certificate to encrypt it for
   `walter-develop/walter-strata-api-key`, and writes only ciphertext to
   `apps/walter-develop/strata-sealedsecret.yaml`. Inspect the file, add
   `  - strata-sealedsecret.yaml` to `apps/walter-develop/kustomization.yaml`,
   and commit both files to this PR. Do NOT commit an unencrypted Kubernetes
   Secret or expose the API key in a terminal transcript.

   Alternatively, provision and seal a dedicated Strata key for this namespace.
   **Do not merge before the new SealedSecret is included:** without it,
   the Deployment cannot mount `walter-strata-api-key` and cannot start.

3. **DNS and TLS.** Point `walter-develop.archaic.work` at the same public
   router address as `walter.archaic.work`. The Gateway uses TLS Secret
   `edge/walter-develop-archaic-work-tls`; confirm cert-manager issues it.

4. **Render and review** from the repository root after adding the ciphertext:

   ```sh
   kubectl kustomize clusters/homelab
   kubectl kustomize apps/walter-develop
   ```

Keep the PR a draft until its secret, image and DNS prerequisites are met.

## Verification after Argo CD sync

```sh
k3s kubectl -n argocd get applications walter walter-develop public-gateway
k3s kubectl get namespace walter-develop --show-labels
k3s kubectl -n walter-develop get deployments,pods,svc,pvc,httproutes,kanidmoauth2clients,sealedsecrets
k3s kubectl -n walter-develop rollout status deployment/walter-develop --timeout=300s
k3s kubectl -n walter-develop get endpointslices -l kubernetes.io/service-name=walter-develop
k3s kubectl -n edge get gateway public
```

Confirm the Kaniop-created `walter-develop-kanidm-oauth2-credentials`
Secret and decrypted Strata key exist in `walter-develop`.
Verify valid HTTPS, allowed and denied login/logout, SSE streaming,
persistence after a restart, and no impact to production conversations.

**Updating to a newer `develop` commit:** publish its image manually,
verify the run, change the pinned reference in `deployment.yaml`, then
merge that GitOps change. Advancing the source branch alone does not update
the Deployment.

Pruning is disabled; explicitly review storage cleanup. OpenEBS hostpath
storage is node-local and deleting its PVC is destructive.
