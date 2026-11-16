# Walter develop test instance

This is a **second** Walter instance at
https://walter-develop.archaic.work, alongside the existing production Walter
at https://walter.archaic.work. Its source is the `develop` branch of
https://github.com/mitschwimmer/walter.

It runs in the existing `walter` Kubernetes namespace to reuse the
already-sealed `walter-strata-api-key`. **This is not a security-isolated
environment:** both instances use the same inference service and bearer key.
It has its own Deployment, Service, HTTPRoute, confidential Kanidm OIDC client
and credentials, and `walter-develop-data` PVC. Never mount or reuse
`walter-data` in the test Deployment. The production manifests are unchanged.

## Before merging into main

1. From https://github.com/mitschwimmer/walter/actions/workflows/oci.yml,
   choose **Run workflow** with branch **develop**. The current deployment is
   pinned to source commit `6a0fcf13fd92050430637cf62538d21a881a23c2` using
   `ghcr.io/mitschwimmer/walter:sha-6a0fcf13fd92050430637cf62538d21a881a23c2`. Confirm the run
   succeeded *for that exact commit* and that the GHCR image is pullable.
   GitHub Actions does **not** publish every `develop` push automatically.
   Prefer replacing the SHA tag with the immutable digest recorded in that
   run's summary or `walter-image` artifact before merging.
2. Create public DNS for `walter-develop.archaic.work` pointing to the
   existing Gateway's public IP, as with `walter.archaic.work`. The public
   Gateway terminates TLS using `walter-develop-archaic-work-tls` in `edge`;
   verify cert-manager has issued it.
3. Keep the production `walter` Application and `walter-data` PVC in place.
   The existing `walter` namespace and sealed Strata key must be present.
   Kaniop will provision the separate
   `walter-develop-kanidm-oauth2-credentials` Secret.

## Verify

```sh
k3s kubectl -n argocd get applications walter walter-develop public-gateway
k3s kubectl -n walter get deployments,pods,svc,pvc,httproutes,kanidmoauth2clients
k3s kubectl -n walter rollout status deployment/walter-develop --timeout=300s
k3s kubectl -n walter get endpointslices -l kubernetes.io/service-name=walter-develop
k3s kubectl -n edge get gateway public
```

Confirm both sites resolve and serve valid HTTPS, the new Kanidm client
is Ready, authorized login/logout works, unauthorized users are rejected,
SSE streaming works, and test conversations persist after a restart. Check
the `groups` claim and the configured allow-list if login is rejected.
Verify that production conversations remain untouched.

**Updating to a newer `develop` commit:** manually run the Walter OCI
workflow on `develop`, verify the published image, change the SHA tag or
digest in this directory's `deployment.yaml`, and merge that GitOps
update. Merely advancing the source branch does not update this Deployment.
Do not use an unpinned moving tag for a persistent test service.

This Application has pruning disabled, so deleting its Git resources does
not automatically delete the persistent volume. Back up test data if needed
and make any destructive cleanup an explicit decision.
