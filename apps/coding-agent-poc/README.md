# Coding-agent proof of concept

One Agent Sandbox runs OpenCode Web in Kata. The sandbox can reach a task-specific internal Envoy proxy on TCP 8443. Envoy injects independent Git and JSON bearer credentials from Kubernetes Secrets. A disposable HTTPS fixture serves a one-commit Git repository and one protected JSON endpoint. Both TLS hops are verified. The sandbox mounts only a public CA certificate, temporary space and its workspace. It has no Kubernetes API token or DNS permission.

The approved capability consists of Git clone/fetch and `GET /private`. The HTTPS gateway has no catch-all route. The fixture verifies both credentials independently and returns a fixed JSON response for the protected endpoint. OpenCode listens on guest loopback for an administrator-only browser session. The PoC has no model-provider route, so it exercises the OpenCode task environment without sending LLM requests.

## Homelab prerequisites

The PoC uses the topology in [nix-config at 0998e79](https://github.com/mitschwimmer/nix-config/tree/0998e79411cb45f66ee9780bcd7b2984c58c930c) and [argo at 61cf031](https://github.com/mitschwimmer/argo/tree/61cf03163ae6cbfb20693718683a60e5520d6489). Those are repository settings. Check the effective configuration on the target cluster.

- Confirm `k8s-worker-02` is Ready and has the Kata node label, nested KVM, `/dev/kvm`, `/dev/vhost-net` and `/dev/vhost-vsock`. Confirm that the existing Argo-managed `kata-qemu-runtime-rs` RuntimeClass runs a pod. [Homelab Kata runbook](https://github.com/mitschwimmer/nix-config/blob/main/docs/operations.md#prepare-the-kata-worker)
- Confirm Cilium runs with policy enforcement and `socketLB.hostNamespaceOnly=true` when kube-proxy replacement is enabled. The inspected homelab config enables kube-proxy replacement and does not set that socket-LB value. For the homelab, use the Argo-owned `HelmChartConfig/cilium` in `apps/gateway-api/helmchartconfig.yaml` and wait for the resulting Cilium rollout. Review existing Cilium and Kubernetes policies that select these workloads, since allow policies are additive. [Cilium Kata setup](https://docs.cilium.io/en/v1.20/network/kubernetes/kata/)
- Reuse the Envoy Gateway controller in `envoy-gateway-system` and the Gateway API CRDs already owned by Argo. The task Gateway requests a dedicated ClusterIP proxy through a separate GatewayClass. The script checks the generated Service before starting OpenCode. Set `ENVOY_NAMESPACE` if the proxy runs in a different preexisting namespace. The PoC expects standard per-Gateway deployment mode, with the generated proxy outside the sandbox namespace. [Envoy Gateway deployment modes](https://gateway.envoyproxy.io/v1.10/tasks/operations/deployment-mode/)
- Install Agent Sandbox core v1.0.7 through your cluster's normal ownership path if it is absent. The release's core manifest provides `sandboxes.agents.x-k8s.io/v1beta1`. The PoC creates a `Sandbox` directly. [Agent Sandbox core manifest](https://github.com/kubernetes-sigs/agent-sandbox/releases/download/v1.0.7/sandbox.yaml)
- Run the procedure with Bash, kubectl, OpenSSL, and an administrative kubeconfig. Pick a container registry the worker can pull from. Use a digest for the published PoC image during the run.

### Versions and licenses

Reviewed on 2026-11-19. The existing homelab versions below come from source configuration. The Kubernetes server version should be checked on the live cluster against the Envoy Gateway support matrix.

| Component | Version reviewed | License |
| --- | --- | --- |
| [OpenCode](https://github.com/anomalyco/opencode/tree/v2.3.2) | 2.3.2, base image index pinned by digest | MIT |
| [Agent Sandbox](https://github.com/kubernetes-sigs/agent-sandbox/tree/v1.0.7) | 1.0.7, Sandbox API v1beta1 | Apache-2.0 |
| [Envoy Gateway](https://github.com/envoyproxy/gateway/tree/v1.10.0) | 1.10.0 in Argo, Envoy Proxy 1.40.2 | Apache-2.0 |
| [Gateway API](https://github.com/kubernetes-sigs/gateway-api/tree/v1.6.3) | 1.6.3 Standard CRDs in Argo. Envoy Gateway 1.10 bundles 1.6.1 and tests Kubernetes 1.34–1.37. | Apache-2.0 |
| [Kata Containers](https://github.com/kata-containers/kata-containers/tree/4.4.0) | 4.4.0 in Argo, QEMU Rust runtime | Apache-2.0 |
| [Cilium](https://github.com/cilium/cilium/tree/v1.20.4) | 1.20.4 in Nix. Upstream also publishes 1.20.5. | Apache-2.0, with GPL-2.0 datapath files |
| [Kanidm](https://github.com/kanidm/kanidm/tree/v1.12.1) | 1.12.1 in Argo, deferred to portal authentication | MPL-2.0 |
| [Pi](https://github.com/earendil-works/pi-mono/tree/v1.5.2) | 1.5.2, deferred harness | MIT |

## Deploy and verify

Set the target Kubernetes context explicitly. Build and publish the image using your existing image builder. The Docker examples can also be run with compatible Podman commands.

```sh
ctx=YOUR_KUBECTL_CONTEXT
image=YOUR_REGISTRY/coding-agent-poc:20261119

docker build --platform linux/amd64 --tag "$image" .
docker push "$image"
# Use the published image digest for deploy when available.
./poc.sh deploy "$ctx" "$image"
./poc.sh verify "$ctx"
```

The deploy script creates and owns only the `coding-agent-poc` namespace, its unique GatewayClass, and a narrowly selected policy in the Envoy proxy namespace. The environment generates temporary fixture credentials and seven-day certificates. After a partial deploy, use the cleanup command before retrying.

`verify` runs in the same container as OpenCode. It checks for the web shell and the expected mounts, clones the protected Git repo over HTTPS, verifies JSON with both missing and client-supplied authorization, and checks that unapproved paths, methods and Git pushes return 404. It probes direct access to the fixture, Kubernetes API, cluster DNS over TCP, the gateway readiness port and an external IP. Correlate connection failures with Cilium drop verdicts so that ordinary routing failures cannot masquerade as policy enforcement. On the homelab, also check the API VIP and a reachable LAN service from the sandbox with Hubble or the node's Cilium monitor attached.

```sh
hubble observe --from-pod coding-agent-poc/opencode --verdict DROPPED
```

For the browser, run the loopback relay from an administrator workstation with `socat`. It uses the Kubernetes exec API and the image's BusyBox `nc` to reach the guest's loopback listener. Kata's CRI Port-Forward support is still tracked upstream. [Kata issue #1693](https://github.com/kata-containers/kata-containers/issues/1693)

```sh
kubectl --context "$ctx" -n coding-agent-poc logs pod/opencode
socat TCP4-LISTEN:4096,bind=127.0.0.1,reuseaddr,fork \
  "EXEC:kubectl --context $ctx -n coding-agent-poc exec -i pod/opencode -- nc 127.0.0.1 4096"
```

Open <http://127.0.0.1:4096> and use OpenCode's password connection option with the server password from the pod logs. If prompted for the username use `opencode`. The browser terminal can run `git clone https://gateway.poc.test:8443/repo.git` and `curl -fsS https://gateway.poc.test:8443/private` without supplying fixture credentials.

Stop the relay and clean up the task after collecting the results.

```sh
./poc.sh cleanup "$ctx"
```

## Validation status

- Checked manifest schemas against the pinned Agent Sandbox, Cilium, Gateway API, and Envoy Gateway CRDs. Envoy Gateway 1.10.0 translated the Gateway and routes successfully.
- Ran Envoy Proxy 1.40.2 locally with the generated routes and TLS settings. It accepted a Git protocol v2 clone and protected JSON requests with no client credentials, overwrote a client-supplied authorization value, and returned 404 for unapproved requests. The local test supplied certificates and disposable secrets through static Envoy resources.
- Started the pinned OpenCode binary locally and fetched its embedded web UI. No live cluster was available to build and deploy the workload or verify Kubernetes Secret delivery, Kata scheduling, the browser relay, and Cilium policy verdicts end to end.

Once the live checks pass, extend the test in order to MCP Streamable HTTP, a narrowly scoped read-only Kubernetes RBAC profile, concurrent task isolation and cleanup. Record the replica's steady-state CPU, memory and startup time during the concurrent run. Keep the portal behind this infrastructure milestone.
