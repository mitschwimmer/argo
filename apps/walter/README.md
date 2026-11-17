# Walter environments

For future OIDC clients, read the **new application's** documentation
and the shared [Kanidm OIDC preflight checklist](../kanidm/oidc.md)
before registering it. PKCE and group-claim handling vary by application.

The `prd` and `dev` overlays deploy **the same Kubernetes resource names**
into separate namespaces:

| | Production | Development |
|---|---|---|
| Namespace | `walter-prd` | `walter-dev` |
| HTTPS origin | `https://walter.archaic.work` | `https://walter.lan.archaic.work` |
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

## Current GitOps operation

The namespace cutover to `walter-prd` and `walter-dev` has been
operator-verified. Both Argo CD Applications have automated sync,
self-healing, and pruning enabled. Their `PruneLast=true` setting prunes
obsolete stateless resources after other sync work succeeds.

Potentially destructive objects in both namespaces (Namespace, PVC,
KanidmOAuth2Client and Strata SealedSecret) are marked
`Prune=confirm,Delete=confirm`. They require an explicit Argo CD prune
confirmation. The root `homelab` application can automatically remove
legacy Argo CD child objects that are no longer declared in Git.

### Legacy cleanup

The old `Application/walter` and `AppProject/walter` are no longer
declared in Git, and their removal is authorized following the verified
cutover. Once root pruning is enabled, Argo CD may delete them. The old
`walter` Kubernetes namespace and its PVC are **not** managed by the
new `walter-prd` or `walter-dev` Applications; root pruning alone does
not guarantee deletion of that namespace. If it still exists, explicitly
remove it after checking that it hosts no required workloads:

```sh
k3s kubectl -n argocd get application walter -o yaml
k3s kubectl -n argocd get appproject walter
k3s kubectl get namespace walter
k3s kubectl -n walter get all,pvc,httproutes,kanidmoauth2clients,sealedsecrets
# After reviewing the above, if the obsolete namespace still exists:
k3s kubectl delete namespace walter
```

Namespace deletion destroys the old `walter/walter-data` OpenEBS
hostpath volume and any old conversations. This data loss has been
explicitly accepted for the cutover. Do not delete `walter-prd` or
`walter-dev`. If legacy Argo CD objects linger, inspect their finalizers
and the root application's live sync status before manually deleting them.
Never force-remove a finalizer without diagnosing its controller.

These cleanup commands are **not** performed by GitOps changes or this PR.
The Strata SealedSecrets for the two new namespaces are already committed
and included in their respective Kustomizations.

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

## Automatic development deployment

Walter's `develop` branch CI publishes each tested build to GHCR with both
`sha-<commit>` and the moving `develop` tag. The `develop` tag is only
an **image discovery mechanism**, not the Kubernetes Deployment reference.

The Argo repository's `.github/workflows/sync-walter-develop.yaml` checks
the public GHCR tag every 15 minutes (and supports `workflow_dispatch`).
When its digest changes, GitHub Actions updates exactly
`apps/walter/dev/deployment.yaml` with an immutable
`ghcr.io/mitschwimmer/walter@sha256:...` reference and commits to `main`.
The existing `walter-dev` Argo CD Application then syncs that Git commit
automatically. No external GitHub PAT or Kubernetes credentials are needed:
this repository's GitHub Actions `GITHUB_TOKEN` requires `contents: write`,
and GHCR must allow public image pulls. Repository branch protections must
permit the automation's GitHub Actions bot to push to `main` (or this step
will fail until a permitted write-back mechanism is configured).

GitHub scheduled workflows are not guaranteed to start on time. A successful
image publish usually reaches GitOps after the next scheduled run, rather
than instantly. You can trigger **Sync Walter develop image** manually in
the Argo repository's Actions tab for faster reconciliation.

Production remains pinned to its independently reviewed digest. The updater
does **not** modify `apps/walter/prd/`, secrets, namespaces, or any other
workloads. If the GHCR tag is not yet published, the previous dev image
reference remains untouched.

### Verification

1. Merge the Walter CI change into `develop` and confirm its image job
   passes (including the browser tests) and publishes `:develop`.
2. Merge the Argo workflow; trigger `Sync Walter develop image` once,
   then check its run and the automated commit to `main`.
3. Check `argocd/Application/walter-dev` is Synced/Healthy and that
   `walter-dev/Deployment/walter` uses the digest committed in Git.

```sh
k3s kubectl -n argocd get application walter-dev
k3s kubectl -n walter-dev rollout status deployment/walter --timeout=300s
k3s kubectl -n walter-dev get deployment walter -o jsonpath='{.spec.template.spec.containers[0].image}'
```

