# Argo CD internal UI and Kanidm OIDC

The Argo CD HelmChart, ConfigMaps and server parameters remain owned by
[`nix-config/kubernetes/argocd.nix`](https://github.com/mitschwimmer/nix-config/blob/main/kubernetes/argocd.nix).
Do not install another Argo CD Helm release in this repository.

This Argo CD Application owns only a Gateway API HTTPRoute and Kaniop client.

- UniFi local A record: `argocd.lan.archaic.work -> 192.168.1.202`
- Gateway: `edge/lan` HTTPS, using wildcard certificate `lan-archaic-work-tls`
- Backend: `argocd/argocd-server:80`, HTTP after TLS termination at Envoy
- Kanidm OIDC issuer: `https://auth.archaic.work/oauth2/openid/argocd`
- Client: `argocd`, callback `https://argocd.lan.archaic.work/auth/callback`
- Membership: Kanidm group `argocd-admins` includes `henner`
- Group claim: `admin` for group members, mapped to Argo CD `role:admin`

Kanidm already uses `admin` as a service-account identity; instead of
creating a conflicting Kanidm group, `argocd-admins` maps to an OIDC
`admin` group claim. This grants **Argo CD** privileges, not Kanidm admin.

Kaniop v0.23.0 creates `argocd/argocd-kanidm-oauth2-credentials` with
`CLIENT_SECRET`. The `secretTemplate` applies the label
`app.kubernetes.io/part-of: argocd`, allowing Argo CD to reference it
through `$argocd-kanidm-oauth2-credentials:CLIENT_SECRET` without copying
or committing the secret.

## Merge order

1. Verify LAN Gateway wildcard TLS certificate is Ready, and Kanidm/Kaniop
   are healthy. Merge the `argo` change and confirm its new Kanidm group,
   client and generated Secret are Ready.
2. Merge the companion `nix-config` PR, which updates the **existing**
   K3s-owned Argo CD HelmChart with the URL, `server.insecure`, OIDC and
   admin-only RBAC mapping. During the gap between merges, the route
   may not work because the server still expects TLS on its service port.
3. Confirm Kanidm login as `henner` grants administrator permissions.
   Test that accounts outside `argocd-admins` have no Argo CD rights.
   Retain Argo CD's local administrator account as break-glass access until
   the flow is validated.
4. Keep `192.168.1.202` off the public WAN forwarding path. Restrict
   access from untrusted VLANs in UniFi; DNS is not an access-control layer.

## Verification

```sh
kubectl -n kanidm get kanidmgroups argocd-admins
kubectl -n argocd get kanidmoauth2clients argocd
kubectl -n argocd get secret argocd-kanidm-oauth2-credentials --show-labels
kubectl -n argocd get httproute argocd -o yaml
kubectl -n edge get gateway lan
kubectl -n edge get certificate lan-archaic-work-tls
dig @<UNIFI_DNS_IP> argocd.lan.archaic.work A
```

Check the Secret's `app.kubernetes.io/part-of=argocd` label and
the OAuth2 client's Ready status before enabling OIDC in the HelmChart.
