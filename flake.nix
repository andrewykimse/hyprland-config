{
  description = "Hyprland configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    # Not system-namespaced: home-manager consumes this module directly and
    # resolves pkgs from the importing configuration.
    homeManagerModules.default = import ./nix/default.nix;
  };
}
