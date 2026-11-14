# Application manifests

Place each workload's Kubernetes manifests or Kustomize overlay in its own
subdirectory here. Declare its Argo CD Application and a suitably scoped
AppProject under `clusters/homelab/`, and include those files explicitly in
that directory's `kustomization.yaml`.

The bootstrap project only manages Application and AppProject objects in
`argocd`. Workload projects must explicitly allow their required source
repositories, destination namespaces and resource kinds. Prefer narrowly
scoped projects to an unrestricted default project.

Argo CD manages desired manifests, not a Helm release installed by K3s.
Do not introduce applications that manage the existing Cilium or Argo CD
bootstrap resources while K3s's Helm Controller still owns those resources.
