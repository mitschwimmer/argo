# Kanidm theme distribution

The Kanidm UI theme is maintained in
[archaic-work/kanidm-theme](https://github.com/archaic-work/kanidm-theme).
This GitOps overlay consumes that repository as a **commit-pinned remote
Kustomize base** rather than copying the stylesheet or downloading it at Pod
startup.

## Deployment

The remote base in [`kustomization.yaml`](kustomization.yaml) generates a
content-hashed `kanidm-theme` ConfigMap in the `kanidm` namespace. The
[`kustomizeconfig.yaml`](kustomizeconfig.yaml) name-reference rule updates
`Kanidm.spec.volumes[].configMap.name` to match the generated name.
Kaniop mounts its `override.css` key read-only at
`/hpkg/override.css`. Do **not** mount over all of `/hpkg`.

No theme image, container registry, cluster-side downloader, or duplicated
theme source is needed. The Argo CD repo-server must be able to clone the
public theme repository over HTTPS when rendering this Application.

## Update procedure

1. Merge and visually review changes in the theme repository.
2. Replace the full commit SHA in the remote Kustomize resource URL with
   the **merged** theme commit. Do not track `main` or a mutable branch.
3. Render `kubectl kustomize apps/kanidm` and verify that the generated
   ConfigMap contains `override.css` and the Kanidm CR references its exact
   hashed name. Also inspect `argocd app diff kanidm`.
4. Review login and account UI behavior in both light and dark modes, on
   desktop and mobile. Confirm the theme's visual test run targets the
   **deployed Kanidm version** before promotion.
5. Merge the Argo PR only after validation. Argo CD automatically syncs it.
   The CSS uses a Kubernetes `subPath` mount, so changing the ConfigMap
   does **not** update existing Pods. Confirm Kaniop performs a controlled
   Pod rollout, or schedule an explicit restart.

The current cluster pins **Kaniop v0.22.1** and **Kanidm 1.11.2** while
the theme repository's visual CI currently targets **Kanidm 1.12.1**.
That mismatch must be tested or resolved before deployment. Changing Kanidm
and Kaniop versions is intentionally outside the scope of this theme PR.

## Rollback

Revert the Argo theme pin and reconcile the application, then ensure the
Kanidm Pod reloads the previous CSS. Argo CD pruning is disabled; old
content-hashed ConfigMaps may persist after a rollback or update.
