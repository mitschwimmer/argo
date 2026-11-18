# Homelab GitOps

Declarative Kubernetes configuration reconciled by Argo CD.

Before registering a new application with Kanidm, **check the application's
OIDC documentation** against the [client preflight
checklist](apps/kanidm/oidc.md), especially PKCE support, callback URLs,
group-claim format and authorization behavior.

## Ownership

- [nix-config](https://github.com/mitschwimmer/nix-config) owns NixOS hosts,
  MicroVMs, K3s, and the bootstrap HelmCharts for Cilium and Argo CD.
- This repository owns the `homelab` root Application, its bootstrap project,
  and workload Applications, projects and manifests.
- Each resource has one reconciler. Do not manage bootstrap Helm resources
  from an Argo CD Application until a separately reviewed ownership handover.

This repository is public. Do not commit passwords, join tokens, private keys
or plaintext Secret resources. Public HTTPS checkout requires no GitHub token.

## Initial bootstrap

1. Merge the initial GitOps structure here before bootstrapping the root.
2. Install the pinned Argo CD HelmChart through the NixOS configuration and
   verify its pods and CRDs are ready, following `nix-config/docs/gitops.md`.
3. From this checkout on your workstation, apply the root once through an
   existing server. Set `CP01_IP` to its actual address:

   ```sh
   ssh root@"$CP01_IP" 'k3s kubectl apply -f -' \
     < clusters/homelab/bootstrap.yaml
   ```

   SSH intentionally reads the YAML on stdin here; do not add `-n` to this
   command. The two objects are an AppProject and an Application; no namespace,
   workload or existing infrastructure is adopted implicitly.
4. Verify the `homelab` Application is Synced and Healthy. It renders
   `clusters/homelab/kustomization.yaml`, including its own definition and
   project. Subsequent edits are reconciled from `main` automatically.

The root has automated sync, self-healing and pruning enabled. It prunes
low-risk Application/AppProject definitions; critical child Applications and
AppProjects use `Prune=confirm,Delete=confirm` and require explicit approval.
The root and critical child Applications have no cascading-delete finalizers.
Only the disposable `hello-world` and stateless `sealing-certificate`
Applications opt in to cascading deletion when removed from Git. Inspect
live finalizers before deleting any other child Application.

## Safe automatic pruning

Argo CD cannot infer whether deleting a resource will lose data. Use
resource-level `argocd.argoproj.io/sync-options:
Prune=confirm,Delete=confirm` for persistent or high-impact objects, and
`prune: true` on an Application only when remaining resources are safe to
remove automatically. `Delete=confirm` also protects against cascading
Application deletion through Argo CD; it does **not** prevent an administrator
from deleting the namespace directly with `kubectl`.

- The `homelab` root auto-prunes low-risk Application/AppProject definitions.
  Disposable `hello-world` and stateless `sealing-certificate` carry
  cascading-delete finalizers, so removing them from the root also prunes
  their workloads. Critical child Applications and projects require manual
  approval; they intentionally have no cascading-delete finalizer, so
  removal from the root may orphan resources rather than clean up workloads.
- `hello-world`, `sealing-certificate`, `public-gateway`, and `kanidm`
  have automatic pruning. The public Gateway and its namespace require
  confirmation; Kanidm's database CR, user/group CRs, certificate and
  namespace require confirmation. Other transient resources may be pruned.
- `walter-prd` and `walter-dev` reconcile and prune automatically
  after the verified namespace cutover. Stateless resources are pruned;
  namespace, PVC, OIDC client and encrypted Strata credential require
  confirmation before pruning.
- `openebs`, `sealed-secrets`, `kaniop`, `gateway-api`,
  `cilium-networking`, and `cert-manager` retain `prune: false`.
  Their Helm charts, CRDs, storage or CNI dependencies make unreviewed
  deletion an infrastructure and potential data-loss risk.
- Keep `allowEmpty: false`. `PruneLast=true` on auto-pruning Applications
  defers pruning until replacement resources are applied and healthy.
  An object awaiting confirmation will remain pending until explicitly
  approved; treat it as a deliberate review, not a stuck reconciliation.

**Before merging changes that enable root pruning**, inspect the live
Argo CD diff for `homelab` and its children. The Walter namespace cutover
has been operator-verified, and legacy `Application/walter` and
`AppProject/walter` are approved for removal. They are absent from Git:
root pruning may remove those live Argo CD objects once enabled. The
legacy `walter` namespace and its PVC are separate Kubernetes resources;
remove them explicitly if they still exist. First inspect any live Argo CD
Application finalizers, which could cause cascading workload deletion.
Review **all other** pending root prunes before merging; a Git annotation
cannot guard an already-orphaned live resource that is no longer declared
in Git. Verify restorable backups before approving deletion of Kanidm
state or current Walter PVCs. Never assume a confirmation prompt itself
makes a destructive deletion safe.

## Gateway API and Cilium networking

### Ownership

`nix-config` owns **only the bootstrap Cilium HelmChart**, installed by
cp-01's K3s Helm Controller. Its Helm values define the API VIP, CNI paths,
native routing, kube-proxy replacement and Kubernetes IPAM so networking
works **before Argo CD starts**.

This repository does not create another Cilium Helm release. Argo owns the
`HelmChartConfig/cilium` resource in `kube-system`, which overrides optional
values in the **same K3s-owned release**: Gateway API, standalone Envoy,
L2 announcements, `lan0` device selection and API client rate limits.
Its `operator.rollOutPods` and `rollOutCiliumPods` options explicitly
restart the operator and agent Pods on Cilium ConfigMap changes (both
options default to `false` in Cilium 1.20.4).
Both Helm resources share the name `cilium` and namespace `kube-system`.
The override uses `failurePolicy: abort` to preserve the bootstrap chart's
non-destructive failure policy. A chart upgrade triggered by this resource
can still affect core cluster networking; review its diffs carefully.

Two child Applications divide independently managed resources:

- `gateway-api` installs the seven **standard** Gateway API v1.6.3 CRDs
  required by Cilium 1.20.4, pinned to upstream Git and applied server-side.
  Its local source also manages the Cilium `HelmChartConfig` and the
  `cilium` GatewayClass (`io.cilium/gateway-controller`). Cilium's chart
  has `gatewayClass.create: false` to prevent duplicate ownership.
- `cilium-networking` declares Cilium's `CiliumLoadBalancerIPPool` and
  `CiliumL2AnnouncementPolicy` custom resources, **not** its DaemonSet
  or HelmChart.

### Startup and ordering

Argo's `gateway-api` Application applies CRDs at wave 0, then the
`HelmChartConfig` at wave 1, then `GatewayClass/cilium` at wave 2. Argo
waits for resource health between waves. This works on a fresh cluster
where Cilium must start first: it boots with Gateway API disabled, Argo
installs the definitions, then K3s upgrades the existing Cilium release
when the Argo-managed override arrives. The chart upgrade and checksum-based Pod-template updates roll the
Cilium operator and agent onto the new features; confirm that with live checks.
No one-time manual operator restart is part of the intended normal path.

The `gateway-api` child Application retains `prune: false`. Removing a
`HelmChartConfig` file from Git therefore **does not** automatically delete
the live override. Treat changes or removal as a networking operation. If an
override disrupts Cilium, use K3s control-plane access to inspect the
`HelmChart` and `HelmChartConfig`; revert the bad values in Git. If
Argo is unavailable, ensure its automated reconciliation will not
recreate the faulty resource before removing the live override. The
bootstrap HelmChart in `nix-config` remains the recovery baseline.
Do **not** delete or duplicate the bootstrap `HelmChart/cilium`.

### LAN IP allocation and announcements

`CiliumLoadBalancerIPPool/lan-gateways` is enabled for the reserved
`192.168.1.201-192.168.1.220` block (20 addresses). The router's DHCP
scope ends at `192.168.1.200`, and the network operator confirmed
addresses above that were free. Keep these twenty IPs out of DHCP
expansions, static device assignments and other load balancer pools.
The Kubernetes API VIP `192.168.1.110` is separate.

Only Services created by Cilium Gateways are eligible for allocation and
announcement, selected via `gateway.networking.k8s.io/gateway-name`.
`CiliumL2AnnouncementPolicy/gateway-services` announces LoadBalancer IPs
over `lan0` from `k8s-cp-01`, `k8s-cp-03` or `k8s-worker-02`
(the small, tainted cp-02 is excluded). A Kubernetes Lease elects a single
announcer for each Service. This is L2 VIP failover, not application
replication; the feature is still beta upstream. Gateway Services use
`externalTrafficPolicy: Cluster`, which is compatible with L2
announcements.

No Gateway, HTTPRoute, DNS name or listener is created yet, so enabling
these resources does **not** expose an application to the LAN.

After merging, on a K3s server verify:

```sh
k3s kubectl -n argocd get applications gateway-api cilium-networking
k3s kubectl wait --for=condition=Established --timeout=300s \
  crd/gatewayclasses.gateway.networking.k8s.io \
  crd/gateways.gateway.networking.k8s.io \
  crd/httproutes.gateway.networking.k8s.io \
  crd/grpcroutes.gateway.networking.k8s.io \
  crd/backendtlspolicies.gateway.networking.k8s.io \
  crd/referencegrants.gateway.networking.k8s.io \
  crd/tlsroutes.gateway.networking.k8s.io
k3s kubectl -n kube-system get helmchart cilium
k3s kubectl -n kube-system get helmchartconfig cilium -o yaml
k3s kubectl -n kube-system rollout status deployment/cilium-operator --timeout=300s
k3s kubectl wait --for=condition=Accepted gatewayclass/cilium --timeout=300s
k3s kubectl get ciliumloadbalancerippools,ciliuml2announcementpolicies
```

Once a Gateway and HTTPRoute are added, check that its generated
LoadBalancer Service receives an address from the reserved block, another
LAN host can reach it over ARP and HTTP, and it remains reachable after
a controlled announcer failover. Do not disrupt etcd to test L2 failover.

## Storage

The `openebs` child Application installs the pinned OpenEBS
`localpv-provisioner` Helm chart, **not** the umbrella chart or any replicated
storage engine. Its `openebs-hostpath` StorageClass is the cluster default,
with `WaitForFirstConsumer` binding and `Delete` reclaim policy. The
provisioner stores data under `/var/openebs/local` on the selected Kubernetes
node. This is on each MicroVM's persistent `/var` state image, not a shared
filesystem. The K3s `local-storage` provisioner is disabled in `nix-config`.

Volumes are tied to their node: a node/disk loss makes its data unavailable,
and rescheduling a workload to a different node does **not** move its data.
Deleting a PVC with the `Delete` policy destroys its volume directory.
A requested PVC size is **not** a disk-space quota with this configuration;
monitor real node filesystem usage. Rebuilding a MicroVM with a fresh state
image destroys its local volumes. Back up application data separately before
rebuilding or deleting PVCs.

After synchronization, check the controller and StorageClass from a K3s server:

```sh
k3s kubectl -n argocd get applications
k3s kubectl -n openebs get deployments,pods
k3s kubectl get storageclasses
k3s kubectl get storageclass openebs-hostpath -o yaml
```

A PVC using `storageClassName: openebs-hostpath` binds after a consuming
Pod is scheduled. Test a new disposable PVC and Pod, verify that they bind
and mount correctly, and delete them after testing. Neither Argo CD nor
the storage class automatically replicates or backs up volume contents.

## Kata Containers hello site

The `kata-deploy` Application installs the QEMU runtime on `k8s-worker-02`
after the worker is opted in. The existing `hello-world` Deployment requests
`kata-qemu-runtime-rs`. It keeps its previous replica and ConfigMap during the
rollout until the replacement passes its HTTP readiness probe.

In the worker's NixOS guest, ensure nested virtualization is available and
load the KVM and virtio modules before enabling the installer. Persist these
modules in the worker's `boot.kernelModules` in `nix-config` for reboots.
Check the devices inside the worker guest:

```sh
sudo modprobe -a kvm_intel vhost_net vhost_vsock
test -c /dev/kvm && test -c /dev/vhost-vsock
```

After those checks pass, opt the worker in from a K3s server. The installer
restarts the worker's K3s service to register the runtime. Argo CD runs on
this worker, so schedule that restart for a maintenance window.

```sh
k3s kubectl label node k8s-worker-02 archaic.work/kata-ready=true
k3s kubectl wait --for=jsonpath='{.metadata.labels.katacontainers\.io/kata-runtime}'=true \
  node/k8s-worker-02 --timeout=10m
k3s kubectl -n kata-system rollout status daemonset/kata-deploy --timeout=10m
k3s kubectl -n hello-world rollout status deployment/hello-world --timeout=5m
k3s kubectl -n hello-world get pods -l app=hello-world \
  -o 'custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,RUNTIME:.spec.runtimeClassName'
curl -fsS https://hello.archaic.work/ | grep -F 'Hello from Kata Containers'
```

The Ready hello pod should show `kata-qemu-runtime-rs` on `k8s-worker-02`.
The same greeting should appear when opening https://hello.archaic.work/.

## Add a workload

Put its configuration under `apps/<name>/`. Add an Application and scoped
AppProject under `clusters/homelab/`, explicitly list them in the root
kustomization and open a pull request. Review changes before merging to
`main`: writers of root Applications/AppProjects are cluster administrators.
The OpenEBS storage provisioner is infrastructure; add other workloads
separately.

## Validate

```sh
kubectl kustomize clusters/homelab
```

Render before merging and inspect the actual resource set. Do not use
`kubectl apply` for routine changes after the one-time root bootstrap; commit
those desired changes here instead. Manual changes are reconciled back to Git.
