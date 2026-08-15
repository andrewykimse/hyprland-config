{
  description = "Hyprland configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Source trees, not flakes: the Quickshell rice is patched at build time by
    # nix/quickshell.nix rather than consumed as a package.
    ricelin = {
      url = "github:Gakuseei/Ricelin";
      flake = false;
    };
    hyprsphere = {
      url = "github:66-firebat/hyprsphere";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, ricelin, hyprsphere }: {
    # Not system-namespaced: home-manager consumes this module directly and
    # resolves pkgs from the importing configuration. The module is a function
    # of the source inputs so consumers don't have to thread them through
    # extraSpecialArgs themselves.
    homeManagerModules.default = import ./nix/default.nix { inherit ricelin hyprsphere; };
  };
}
