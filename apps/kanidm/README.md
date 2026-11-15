# Kanidm theme

Industrial dark styling for the Kanidm login, OAuth2 authorization, device
login and account portal. The visible identity is "ARCHAIC", with a technical
monospaced treatment, restrained grid background, high-contrast neutral
buttons, minimal red indicators, and consistent **8pt** surface radii
(approximately 10.67 CSS pixels).

Pure CSS, without JavaScript, downloaded fonts, or external assets on login
pages. The stylesheet is tailored to the pinned Kanidm **1.11.2** templates.

The source is [`override.css`](override.css). Kustomize generates a
content-hashed `kanidm-nothing-theme` ConfigMap, and
[`kustomizeconfig.yaml`](kustomizeconfig.yaml) rewrites its name reference in
the `Kanidm` custom resource. Kaniop mounts the file at the upstream-supported
`/hpkg/override.css` path. Keep that mount in place; do not mount over `/hpkg`.

## Branding limitations

Kanidm's templates still own the domain display-name text and icons. For a
white-label visual appearance this CSS hides the upstream logo and the
"Powered by Kanidm" footer, and visually replaces the large login/portal
identity text with "ARCHAIC". It **does not** modify Kanidm's server-rendered
semantics: assistive technologies may still announce the configured domain
display name. Set the actual Kanidm domain display name to "ARCHAIC" through
its administration interface as a separate, reviewed operational change.

The browser tab title (`Login - Kanidm`) and stock favicon originate in the
server templates and cannot be replaced using CSS alone. Do not inject scripts
or proxy substitutions into authentication responses to hide those strings.

## Validation

Before merging, render the existing Argo application:

```sh
kubectl kustomize apps/kanidm > /tmp/kanidm-rendered.yaml
```

Confirm the generated ConfigMap has an `override.css` data key and its hashed
name matches `spec.volumes[].configMap.name`. After merging, Argo CD will
reconcile the generated ConfigMap and the Kaniop-managed Kanidm resource.
The CSS is mounted with `subPath`, so verify that reconciliation actually
restarts the server pod to pick up the new stylesheet; restart the rollout
deliberately if it does not.

In the browser, hard-refresh `https://auth.archaic.work` and check that the
CSS is served from `/pkg/override.css`. Inspect the username entry, password,
TOTP, passkey/security-key choice, OAuth2 consent, device authorization,
credential reset, profile and admin pages. Check small screens, keyboard focus,
alerts and errors. The upstream template includes extra identity labels in
credential reset and the browser title; this CSS intentionally avoids hiding
those functional details.

For rollback, revert the CSS commit and allow Argo CD / Kaniop to reconcile.
Generated ConfigMaps might remain because the Argo CD Application has pruning
disabled.
