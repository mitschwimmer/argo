# Sealed Secrets public certificate over HTTPS

This Application exposes only `GET /v1/cert.pem` from the existing
`sealed-secrets-controller` Service in the `sealed-secrets` namespace.
The existing Cilium Gateway `edge/public` terminates HTTPS at its fixed
`192.168.1.201` address; there is no new gateway or load balancer.

- Host: `seal.lan.archaic.work`
- URL: `https://seal.lan.archaic.work/v1/cert.pem`
- TLS Secret: `edge/seal-archaic-work-tls` (cert-manager creates it from
  the existing `letsencrypt-production` ClusterIssuer)
- Backend: `sealed-secrets/sealed-secrets-controller:8080`
- Gateway listener: `https-seal`, restricted to HTTPRoutes from only the
  `sealed-secrets` namespace using the built-in namespace name label
- HTTPRoute: exact path and GET method only

## DNS and public exposure

Create the `seal.lan.archaic.work` public DNS record pointed at the same WAN
address as `auth.archaic.work`. The router already forwards TCP 80/443 to
`192.168.1.201`. The existing HTTP listener supports cert-manager's ACME
HTTP-01 challenge; the HTTP redirect includes the sealing hostname.

If your router lacks NAT hairpinning, arrange split-horizon LAN DNS for
`seal.lan.archaic.work` -> `192.168.1.201`; keep public DNS correct so
Let's Encrypt can issue the certificate. The HTTPS URL must be reachable
*by your workstation*, with a trusted TLS certificate.

**This endpoint is public on the Internet**, because the existing Gateway
is forwarded from WAN. Only the *public* certificate is available.
Do not add a wildcard or prefix route or publish any controller
management endpoints. The controller's Kubernetes Service remains ClusterIP.

## Workstation use

After the new Gateway certificate is Ready and the HTTPRoute reports
`Accepted=True` and `ResolvedRefs=True`, fetch the sealing certificate:

```sh
curl -fsS https://seal.lan.archaic.work/v1/cert.pem > sealed-secrets.pem
openssl x509 -in sealed-secrets.pem -noout -subject -fingerprint -sha256
```

For the **first** certificate, verify its SHA-256 fingerprint against the
certificate obtained from a trusted K3s administrator/SSH connection.
HTTPS ensures transport integrity, but you must also trust the initial
certificate identity; a substituted sealing certificate could compromise
subsequently published encrypted Secrets.

`kubeseal` accepts the URL directly and refetches the current certificate:

```sh
kubeseal --cert https://seal.lan.archaic.work/v1/cert.pem \
  --format yaml < secret.yaml > sealed-secret.yaml
```

To seal Walter's Strata key locally, using only client-side `kubectl`
(no Kubernetes API connection required), substitute the local file path:

```sh
kubectl create secret generic walter-strata-api-key \
  --namespace walter --from-file=api-key=/secure/path/to/strata-key \
  --dry-run=client --output yaml |
  kubeseal --cert https://seal.lan.archaic.work/v1/cert.pem \
    --format yaml > apps/walter/strata-sealedsecret.yaml
```

Commit only the **SealedSecret**, and include the new file in
`apps/walter/kustomization.yaml`; do not commit a plaintext Secret,
API key, or `secret.yaml`.

## Acceptance

```sh
k3s kubectl -n argocd get applications public-gateway sealing-certificate
k3s kubectl -n edge get certificate seal-archaic-work-tls
k3s kubectl -n edge get gateway public
k3s kubectl -n sealed-secrets get httproute sealing-certificate
k3s kubectl -n sealed-secrets get service sealed-secrets-controller
```

Confirm the actual certificate contents over HTTPS, then ensure a request
to another controller API path on `seal.lan.archaic.work` does **not** route
to the backend. `HEAD /v1/cert.pem` also intentionally does not match.

The controller rotates its *public sealing certificate* periodically.
The URL fetches the current certificate, but **does not replace backups
of the private sealing key**. Preserve those keys securely off-cluster and
test restoration before depending on Sealed Secrets for fresh rebuilds.
