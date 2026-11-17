# Sealed Secrets sealing certificate on the LAN

The `sealing-certificate` Application exposes **only**
`GET /v1/cert.pem` from the existing
`sealed-secrets/sealed-secrets-controller:8080` Service through
the internal Cilium Gateway `edge/lan` on `192.168.1.202`.

- Host: `seal.lan.archaic.work`
- URL: `https://seal.lan.archaic.work/v1/cert.pem`
- TLS: shared wildcard `edge/lan-archaic-work-tls` (Hetzner DNS-01)
- Gateway listener: `edge/lan`, `https`
- HTTPRoute: exact GET path only; no controller API management endpoints

## UniFi and routing

Add a **local** UniFi A record for
`seal.lan.archaic.work -> 192.168.1.202`.
Do not create a public A/AAAA record pointing at the private address
or add any WAN port forwarding to `.202`.

The old public `seal.archaic.work` HTTPS listener and HTTP redirect
are removed from `apps/public-gateway`. Remove any obsolete public
DNS record separately after confirming the LAN route works.

The wildcard certificate is issued through the public authoritative
Hetzner DNS-01 TXT records; avoid shadowing
`_acme-challenge.lan.archaic.work` with an internal authoritative zone.

## Workstation usage

After the LAN wildcard TLS certificate is Ready and the HTTPRoute
is Accepted/ResolvedRefs, fetch the certificate:

```sh
curl -fsS https://seal.lan.archaic.work/v1/cert.pem > sealed-secrets.pem
openssl x509 -in sealed-secrets.pem -noout -subject -fingerprint -sha256

kubeseal --cert https://seal.lan.archaic.work/v1/cert.pem \
  --format yaml < secret.yaml > sealed-secret.yaml
```

Verify the initial sealing-certificate SHA-256 fingerprint through a trusted
K3s administrator/SSH channel. HTTPS protects transport but does not prove
the correct *Sealed Secrets* encryption key was served.

### Recovery before internal TLS is available

A fresh cluster may not yet have a Ready wildcard TLS certificate
(e.g. before its encrypted Hetzner token is restored). Use an authenticated
Kubernetes connection to fetch the certificate instead:

```sh
kubeseal --controller-name sealed-secrets-controller \
  --controller-namespace sealed-secrets --fetch-cert > sealed-secrets.pem
```

For recovery of **previously sealed secrets**, preserve the controller's
private sealing key in off-cluster backups. Fetching a new public certificate
does not restore the old private key.

## Verification

```sh
k3s kubectl -n argocd get applications lan-gateway sealing-certificate
k3s kubectl -n edge get certificate lan-archaic-work-tls
k3s kubectl -n edge get gateway lan
k3s kubectl -n sealed-secrets get httproute sealing-certificate
k3s kubectl -n sealed-secrets get service sealed-secrets-controller
```

Verify GET returns a valid PEM, while other paths and HEAD requests cannot
reach the controller. Confirm the old public HTTPS listener is absent.
