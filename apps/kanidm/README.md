# Kanidm theme

Nothing OS-inspired dark styling for the Kanidm login, OAuth2 authorization, and
account portal pages. Pure CSS; no replacement of Kanidm templates or JavaScript.
Uses system fonts and does not load third-party assets on authentication pages.

The source is [`override.css`](override.css). Kustomize generates a
content-hashed `kanidm-nothing-theme` ConfigMap and
[`kustomizeconfig.yaml`](kustomizeconfig.yaml) rewrites its name reference in
the `Kanidm` custom resource. Kaniop mounts the file at the upstream-supported
`/hpkg/override.css` path. Do not mount over the entire `/hpkg` directory.

## Validation

Before merging, run:

```sh
kubectl kustomize apps/kanidm > /tmp/kanidm-rendered.yaml
```

Confirm the rendered ConfigMap has an `override.css` data key and the Kanidm
`spec.volumes[].configMap.name` uses the **same hashed name**. When merged,
Argo CD will sync the new ConfigMap before the wave-1 Kanidm resource.
Kaniop should then reconcile the generated workload after its mount changes.
Check the rollout rather than assuming it succeeded.

After deployment, confirm `https://auth.archaic.work/pkg/override.css` contains
the stylesheet; test password login, OAuth2 consent/redirects, passkeys and MFA,
credential changes, portal navigation, mobile layout, and keyboard focus.
Verify the final rendered design against the pinned Kanidm 1.11.2 release.
Adjust selectors when upgrading Kanidm.

This change intentionally does not overwrite the site name or site image. Set
those independently with Kanidm's domain customisation commands if desired.
If the custom CSS causes visual problems, revert this change and let the GitOps
controllers reconcile it; investigate any leftover generated ConfigMaps because
this Argo CD Application has pruning disabled.
