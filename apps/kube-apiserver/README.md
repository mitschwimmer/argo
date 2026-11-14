# Kubernetes API VIP (staged)

This application is deliberately **manual-sync**. It defines a Cilium L2
LoadBalancer Service but **no IP pool**: an unused LAN address must first be
reserved outside DHCP. The repository does not record cp-02/cp-03 addresses
or an available VIP; do not guess any of them.

## Design

- The pinned Cilium 1.20.4 HelmChart remains K3s-owned in `nix-config`.
  It must enable L2 announcements and sufficient API client rate limits.
  Argo must **not** install a second Cilium release.
- K3s API servers run as host processes. A small TCP relay Pod on each
  control-plane node forwards port 6443 to its own node IP. An HTTPS
  `/readyz` probe through the relay controls its Service EndpointSlice
  readiness, so dead/unready API servers stop receiving new connections.
- The Service has Cilium's L2 announcer class, no NodePort and
  `externalTrafficPolicy: Cluster`, allowing the L2 announcer on any node
  to forward to a healthy relay on another node. L2 traffic uses `lan0`.
- TLS is **not** terminated. Before connecting through the VIP, set a
  matching K3s `--tls-san` on all three servers in `nix-config`.
- Never configure K3s's join address or Cilium's bootstrap API access to
  require this Service. Set and test Cilium `k8s.apiServerURLs` using the
  actual three control-plane IPs so that losing cp-01 does not prevent Cilium
  lease renewal or startup. The current fixed cp-01 bootstrap setting alone
  is not sufficient for reliable failover.

## Activation gates

1. Confirm etcd quorum, three ready control planes, four healthy Cilium
   agents, and actual cp-02/cp-03 IPs. Verify the candidate VIP on the
   `192.168.1.0/24` LAN is unused and reserved outside DHCP.
2. First deploy and verify the Cilium configuration from `nix-config`;
   preserve the original bootstrap HelmChart and the cp-01 recovery path.
   Complete the `k8s.apiServerURLs` follow-up with all three real IPs.
3. Add a one-IP `CiliumLoadBalancerIPPool` (`/32`) selected **only** by
   `app.kubernetes.io/name: kube-apiserver-vip`, and include it here in
   `kustomization.yaml`. Add that pool kind to the child AppProject's
   cluster resource whitelist. Review the exact VIP before merging.
   Optionally set `lbipam.cilium.io/ips` to the same address on the Service.
4. Add K3s `--tls-san` for the chosen VIP (or its resolvable DNS name) to
   **each** control-plane server and roll them sequentially, rechecking
   etcd quorum, serving certificates and API health after each restart.
5. Sync the `kube-apiserver-vip` child **manually** in Argo CD. Ensure all
   three relays are ready; verify the Service's allocated IP, EndpointSlices,
   announcement policy, Cilium-selected `lan0`, and the L2 lease.
6. Check kubeconfig access over the VIP with real TLS verification and ARP
   on another LAN host. With etcd quorum intact, test one API server down,
   a relay unready, and finally one L2 announcement leader down. Restore and
   recheck between tests; do not interrupt two etcd voters simultaneously.

From a working control-plane node:

```sh
k3s kubectl -n kube-system get ds kube-apiserver-relay
k3s kubectl -n kube-system get pods -l app.kubernetes.io/name=kube-apiserver-relay -o wide
k3s kubectl -n kube-system get svc kube-apiserver-vip
k3s kubectl -n kube-system get endpointslice -l kubernetes.io/service-name=kube-apiserver-vip
k3s kubectl get ciliuml2announcementpolicies,ciliumloadbalancerippools
k3s kubectl -n kube-system get lease cilium-l2announce-kube-system-kube-apiserver-vip
```

This is **not** physical-host HA. cp-01 and cp-02 both run on meawhite:
losing that host loses etcd quorum. An L2 VIP also requires working Cilium
and a reachable cluster API. Direct server IPs remain the recovery path.

References: [Cilium L2 announcements](https://docs.cilium.io/en/stable/network/l2-announcements/),
[LB IPAM](https://docs.cilium.io/en/stable/network/lb-ipam/),
[K3s HA endpoint](https://docs.k3s.io/datastore/cluster-loadbalancer).
