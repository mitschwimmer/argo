{
  description = "Homelab Kubernetes tools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { nixpkgs, ... }: {
    devShells = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        default = pkgs.mkShellNoCC {
          packages = with pkgs; [
            argocd
            jq
            kubecolor
            kubectl
            kubeseal
            kubernetes-helm
            kustomize
            yq-go
          ];
        };
      }
    );
  };
}
