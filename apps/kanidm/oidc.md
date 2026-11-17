# Before registering an OIDC client with Kanidm

**Read the OIDC integration documentation for the exact application version
before creating its `KanidmOAuth2Client`.** Check the application's settings
and defaults instead of assuming another application's working configuration
will apply.

## Preflight checklist

- [ ] **Authorization flow and PKCE:** Does the application support the
  authorization-code flow with PKCE **S256**? Find the setting and confirm
  whether it is enabled by default. Kanidm requires PKCE by default, including
  for confidential clients. Enable it **in the application**; do not weaken
  Kanidm with `allowInsecureClientDisablePkce` to compensate.

- [ ] **Client registration and callback:** Does the application require a
  public or confidential client, and where does its client ID/secret belong?
  Find the exact redirect/callback URI and externally visible base URL in the
  documentation. Set Kaniop's `origin` and `redirectUrl` accordingly.
  Register distinct client IDs for distinct environments.

- [ ] **Scopes and claims:** Identify the OIDC scopes requested by the
  application (at least `openid`, possibly `profile`, `email`, or
  `groups`). Ensure the Kaniop `scopeMap` grants the required scopes to
  the intended Kanidm group. Check whether the application reads groups
  from the ID token, the UserInfo endpoint, or a configurable claim.

- [ ] **Group values and authorization:** Read how the application maps
  OIDC claims to users, roles, or allowed groups, including its **default
  permissions**. Kanidm can emit group UUIDs and fully qualified names
  such as `some-group@auth.archaic.work`; do not assume a short name like
  `admin` or `some-group` appears in the token. Determine which actual
  claim/value the application must match. A Kaniop `claimMap` alone does
  not prove the intended value appears in the claim the application reads.

- [ ] **Configuration and secret ownership:** Find where the application
  reads its OIDC settings and credentials, and what reload/restart it needs
  after a change. Keep secrets out of Git. Kaniop can create confidential
  client credentials in the client's namespace; verify how the application
  consumes them. In this homelab, some application settings are owned by
  [nix-config](https://github.com/mitschwimmer/nix-config), not by Argo CD.

**If the documentation does not establish PKCE support or how group-based
authorization works, investigate that before registering the client.**
Do not treat successful login alone as proof that access controls work.

## Acceptance test after registration

1. Complete one sign-in and inspect the **actual** ID token/UserInfo group
   claims (using the application's User Info view when available). Confirm
   PKCE S256 was sent in the authorization request if login fails.
2. Verify an intended group member receives the correct application role
   and a **nonmember does not gain unauthorized access**. Check the
   application's RBAC/group mapping against the emitted claim strings.
3. If Kanidm displays an unrecoverable error, correlate its operation ID
   with Kanidm logs before changing client settings:

   ```sh
   kubectl -n kanidm get pods
   kubectl -n kanidm logs <kanidm-pod> --all-containers=true --since=30m \
     | grep -F '<operation-id>'
   ```

Do not disable PKCE, grant application-wide administrator permissions, or
paste tokens/client secrets into logs to bypass a failing integration.

## Previous examples

Walter and Argo CD both exposed PKCE or group-claim integration pitfalls.
The specific application settings differ; consult **each new application's
own documentation**, then use this checklist. See
[nix-config PR #70 (Argo CD PKCE)](https://github.com/mitschwimmer/nix-config/pull/70)
and [PR #71 (group RBAC)](https://github.com/mitschwimmer/nix-config/pull/71)
for examples, not reusable OIDC templates.

[Kanidm OAuth2 documentation](https://kanidm.github.io/kanidm/stable/integrations/oauth2.html)
