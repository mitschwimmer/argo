# Homelab GitOps

Declarative Kubernetes configuration reconciled by Argo CD.

## Ownership

- [nix-config](https://github.com/mitschwimmer/nix-config) owns NixOS hosts,
  MicroVMs, K3s, and the bootstrap HelmCharts for Cilium and Argo CD.
- This repository owns the `homelab` root Application, its bootstrap project,
  and future workload Applications, projects and manifests.
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

The initial root has automated sync and self-healing enabled, but automated
pruning disabled. Removing an entry from Git therefore does not automatically
delete its live object. Child applications should make their own explicit
pruning decision. There is no cascading-delete finalizer on the root.

## Add a workload

Put its configuration under `apps/<name>/`. Add an Application and scoped
AppProject under `clusters/homelab/`, explicitly list them in the root
kustomization and open a pull request. Review changes before merging to
`main`: writers of root Applications/AppProjects are cluster administrators.
No workloads are deployed by this initial repository structure.

## Validate

```sh
kubectl kustomize clusters/homelab
```

Render before merging and inspect the actual resource set. Do not use
`kubectl apply` for routine changes after the one-time root bootstrap; commit
those desired changes here instead. Manual changes are reconciled back to Git.
