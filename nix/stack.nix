{ ghc }:
let project = import ./project.nix {};
in with project.pkgs; haskell.lib.buildStackProject {
  inherit ghc;
  name = "kepler";
  buildInputs = [ git secp256k1 zlib ] ++ builtins.attrValues project.buildInputs;
}
