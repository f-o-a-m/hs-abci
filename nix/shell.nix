{}:
let project = (import ./project.nix {});
in project.pkgs.haskellPackages.shellFor {
  withHoogle = true;
  packages = p: builtins.attrValues (project.keplerPackages' p);
  nativeBuildInputs = builtins.attrValues project.buildInputs;
}
