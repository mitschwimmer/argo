# Kanidm OIDC integration checklist

Use this before adding or modifying an OAuth2/OIDC integration. These two
problems recurred during the November 2026 Argo CD integration:

1. Kanidm rejected an authorization request because Argo CD did not send a
   PKCE S256 `code_challenge`.
2. Kanidm login succeeded, but Argo CD showed no Applications because its
   RBAC rule matched `admin`, while the token's `groups` claim actually
   contained `argocd-admins@auth.archaic.work`.

**Authentication and authorization are different tests.** Reaching the
application after OIDC login does not establish that the user has the expected
application role.

## Before deploying a client

1. **Enable PKCE S256 in the application.** Kanidm expects PKCE even for
   confidential clients by default. Do not work around a missing challenge
   with Kaniop's `allowInsecureClientDisablePkce` or Kanidm's insecure
   compatibility switch. Find the *application-side* option instead.

   For the native OIDC integration in Argo CD v3.6.1, set the following
   under `configs.cm.oidc.config` in
   [`nix-config/kubernetes/argocd.nix`](https://github.com/mitschwimmer/nix-config/blob/main/kubernetes/argocd.nix):

   ```yaml
   oidc.config: |
     name: Kanidm
     issuer: https://auth.archaic.work/oauth2/openid/argocd
     clientID: argocd
     clientSecret: $argocd-kanidm-oauth2-credentials:CLIENT_SECRET
     enablePKCEAuthentication: true
     requestedScopes: ["openid", "profile", "groups"]
   ```

2. **Declare scopes and callback correctly.** The Kaniop
   `KanidmOAuth2Client` must have the application's exact HTTPS
   `origin` and callback `redirectUrl`. Its `scopeMap` must grant the
   `openid` scope (plus any other requested scopes, such as `groups`) to
   the intended Kanidm group. Each application/environment needs its own
   Kanidm OAuth2 client ID and credential Secret.

3. **Inspect real claims; never guess group names.** After a successful
   sign-in, inspect the application's User Info or decoded ID-token claims.
   Kanidm may emit both group UUIDs and SPNs. In the observed Argo CD
   session, the `groups` claim included
   `argocd-admins@auth.archaic.work`, **not** the short name `admin`.
   A Kaniop `claimMap` that attempts to emit a custom `admin` value does
   not establish that this value is present in the actual standard
   `groups` claim. Verify the resulting token before writing RBAC.

4. **Map the observed group to an application role.** In Argo CD's
   `argocd-rbac-cm` (`configs.rbac` in the Nix-owned HelmChart), match
   the exact group SPN:

   ```yaml
   policy.default: role:authenticated
   policy.csv: |
     g, argocd-admins@auth.archaic.work, role:admin
   scopes: '[groups]'
   ```

   Do not set `policy.default: role:admin` to fix missing Applications;
   that would grant administrator rights to unrelated authenticated users.
   Test both a member and a nonmember. The UUID shown as the Argo CD
   username is expected and need not match the Kanidm short username.

5. **Check generated credentials before enabling SSO.** Kaniop v0.23.0
   creates `<client-resource-name>-kanidm-oauth2-credentials` in the
   client's Kubernetes namespace with `CLIENT_SECRET`. Argo CD resolves
   `$argocd-kanidm-oauth2-credentials:CLIENT_SECRET` only if the Secret
   has `app.kubernetes.io/part-of: argocd`; use
   `spec.secretTemplate.labels`. Do not copy the client secret into Git.

6. **Respect configuration owners.** This repository owns the
   Kanidm/Kaniop objects in `apps/kanidm` and the OAuth2 clients in
   workload namespaces. Argo CD's HelmChart, OIDC settings and RBAC live
   in `mitschwimmer/nix-config`. A change to `kubernetes/argocd.nix`
   requires updating the `k8s-cp-01` NixOS MicroVM runner through that
   repository's [operations runbook](https://github.com/mitschwimmer/nix-config/blob/main/docs/operations.md).
   Merging an `argo` manifest alone will not activate Helm settings.

## When login fails or permissions are missing

| Symptom | Inspect first |
| --- | --- |
| Kanidm shows an unrecoverable error before login | Authorization URL: is `code_challenge` present with `code_challenge_method=S256`? Correlate the operation ID with Kanidm logs. |
| Kanidm reports a redirect or scope error | Exact `redirectUrl`, client ID, requested scopes and Kaniop `scopeMap` |
| OIDC succeeds but Argo CD shows no Applications or denies actions | Actual User Info `groups` claim vs. `argocd-rbac-cm` `policy.csv` and `scopes` |
| OIDC starts but the callback/token exchange fails | Generated credentials Secret, label, Kaniop client readiness and Argo CD server logs |

Useful read-only checks from a trusted K3s admin shell:

```sh
kubectl -n kanidm get kanidmgroups argocd-admins
kubectl -n argocd get kanidmoauth2clients argocd
kubectl -n argocd get secret argocd-kanidm-oauth2-credentials --show-labels
kubectl -n argocd get configmap argocd-cm -o yaml
kubectl -n argocd get configmap argocd-rbac-cm -o yaml
kubectl -n argocd logs deployment/argocd-server --since=30m
```

For an unrecoverable Kanidm error, copy its **operation ID**, then find the
Kanidm Pod with `kubectl -n kanidm get pods` and search its logs:

```sh
kubectl -n kanidm logs <kanidm-pod> --all-containers=true --since=30m \
  | grep -F '<operation-id>'
```

Inspect Kubernetes resource status and logs rather than printing Secret
contents or sharing session tokens. If the application uses an SSH tunnel for
emergency access, retain it until both OIDC login **and authorization** pass.

## Incident references and upstream documentation

- [Argo CD PKCE correction (nix-config PR #70)](https://github.com/mitschwimmer/nix-config/pull/70)
- [Argo CD full Kanidm group RBAC mapping (nix-config PR #71)](https://github.com/mitschwimmer/nix-config/pull/71)
- [Kanidm OAuth2 documentation](https://kanidm.github.io/kanidm/stable/integrations/oauth2.html)
- [Argo CD native OIDC configuration](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/)
- [Argo CD RBAC](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/)
