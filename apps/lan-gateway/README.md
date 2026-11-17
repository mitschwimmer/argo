# LAN Cilium Gateway

The second Cilium Gateway is `edge/lan` at `192.168.1.202`.
The existing public gateway remains at `192.168.1.201`; the reserved
Cilium LB-IPAM pool and L2 announcement policy already cover both IPs.

This gateway serves HTTPS for `*.lan.archaic.work`. The explicit
`Certificate/lan-archaic-work-tls` in `edge` uses the new
`ClusterIssuer/letsencrypt-hetzner`. The issuer uses Hetzner's official
cert-manager webhook (chart version 0.9.1) with the new Hetzner Cloud DNS
API for Let's Encrypt DNS-01 validation. There is no dependency on WAN
port forwarding or public A records for these internal hostnames.

The wildcard covers `grafana.lan.archaic.work` but not
`lan.archaic.work` or `x.y.lan.archaic.work`.

## Before merging: provide the Hetzner token

1. Verify that the authoritative `archaic.work` zone is managed in
   Hetzner Console, and generate a project API token with DNS read/write
   privileges. Do not use a legacy DNS Console token.
2. Encrypt the token for this cluster with Sealed Secrets, targeting
   Secret `hetzner-dns` in namespace `cert-manager` with key `token`.
   A locally generated Secret can be piped directly to `kubeseal`:

   ```sh
   read -r -s HETZNER_TOKEN
   printf '\n'
   kubectl create secret generic hetzner-dns \
     --namespace cert-manager \
     --from-literal=token="$HETZNER_TOKEN" \
     --dry-run=client -o yaml |
     kubeseal --cert https://seal.lan.archaic.work/v1/cert.pem \
       --format yaml > apps/cert-manager/hetzner-dns-sealedsecret.yaml
   unset HETZNER_TOKEN
   ```

   Verify the sealing-certificate fingerprint through a trusted cluster
   channel as described in `apps/sealing-certificate/README.md`.
3. Add `hetzner-dns-sealedsecret.yaml` to
   `apps/cert-manager/kustomization.yaml`. Commit only the encrypted
   SealedSecret, never the API token or a plaintext Kubernetes Secret.
   **Do not merge until this prerequisite is supplied**. Without the
   token, DNS-01 challenge handling will fail and TLS will remain unready.

## Split-horizon DNS via UniFi

For every internal service, add a local DNS A record on the UniFi Gateway
Lite pointing to `192.168.1.202`; examples:

- `grafana.lan.archaic.work` -> `192.168.1.202`
- `argocd.lan.archaic.work` -> `192.168.1.202`
- `walter.lan.archaic.work` -> `192.168.1.202`
- `seal.lan.archaic.work` -> `192.168.1.202`

Grafana is an example of a future workload. The other three names have
HTTPRoutes managed by Argo CD. The records are only
returned to clients using the UniFi DNS resolver. Check DHCP DNS
settings for each VLAN. Custom client resolvers, browser DoH and VPN
DNS can bypass these overrides. UniFi firmware/Network versions differ
in where custom DNS records are configured.

Keep the public authoritative `_acme-challenge.lan.archaic.work` TXT
records visible to Let's Encrypt. Do not install a private authoritative
`lan.archaic.work` DNS zone that masks public TXT propagation checks.
Do not create public A/AAAA records pointing to the RFC1918 address, or
add a WAN forwarding rule to `.202`. Existing WAN forwarding to `.201`
is not changed.

Internal DNS does not imply firewall isolation. Restrict VLAN and VPN
access with UniFi firewall rules if necessary.

## Attach an internal service

Create an HTTPRoute in the application's namespace, referencing the
`edge/lan` Gateway and its `https` listener. No namespace labels are needed:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: grafana
  namespace: monitoring
spec:
  parentRefs:
    - name: lan
      namespace: edge
      sectionName: https
  hostnames:
    - grafana.lan.archaic.work
  rules:
    - backendRefs:
        - name: grafana
          port: 80
```

No application is exposed by deploying the gateway alone. Only the
redirect route in `edge` can attach to the cleartext HTTP listener.
The HTTPS listener accepts routes from any namespace for hostnames
matching `*.lan.archaic.work`. Restrict who can create HTTPRoutes using
Kubernetes RBAC if namespace owners are not fully trusted.

## Verify after deploying

```sh
k3s kubectl -n argocd get applications cert-manager hetzner-dns-webhook lan-gateway
k3s kubectl -n cert-manager get deployment cert-manager-webhook-hetzner
k3s kubectl get apiservice v1alpha1.acme.hetzner.com
k3s kubectl get clusterissuer letsencrypt-hetzner
k3s kubectl -n edge get certificate lan-archaic-work-tls
k3s kubectl -n edge get gateway lan
k3s kubectl -n edge get httproute lan-redirect-to-https
```

From a client on the LAN, substitute the actual UniFi resolver IP:

```sh
dig @<UNIFI_DNS_IP> grafana.lan.archaic.work A
curl --resolve grafana.lan.archaic.work:443:192.168.1.202 \
  https://grafana.lan.archaic.work/
```

The DNS result should be `192.168.1.202` once the local record exists.
The TLS handshake should validate after the certificate becomes Ready;
without a deployed matching HTTPRoute, an HTTP 404 is expected.
If issuance fails, inspect Certificate, CertificateRequest, Order and
Challenge resources in `edge`, and the webhook logs.
