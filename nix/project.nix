{ }:
let
  pkgs = import (builtins.fetchTarball {
    name = "master";
    url = https://github.com/nixos/nixpkgs/archive/7fd5059f58dd5c50975579e2e87ca1294bbc845a.tar.gz;
    sha256 = "0b4q30vrzmh40w3k37yzdiyl9fmh40qfjfa922mv9lfv1rmcbdrv";
  }) { inherit overlays; };

  gitignore = pkgs.fetchFromGitHub {
    owner = "hercules-ci";
    repo = "gitignore";
    rev = "f9e996052b5af4032fe6150bba4a6fe4f7b9d698";
    sha256 = "0jrh5ghisaqdd0vldbywags20m2cxpkbbk5jjjmwaw0gr8nhsafv";
  };
  gitignoreSource = (import gitignore {}).gitignoreSource;

  iavl = pkgs.callPackage ./iavl.nix {};
  tendermint = pkgs.callPackage ./tendermint.nix {};

  root = ../.;

  packages = {
    hs-abci-extra = root + /hs-abci-extra;
    hs-abci-sdk = root + /hs-abci-sdk;
    hs-abci-server = root + /hs-abci-server;
    hs-abci-test-utils = root + /hs-abci-test-utils;
    hs-abci-types = root + /hs-abci-types;
    hs-iavl-client = root + /hs-iavl-client;
    hs-tendermint-client = root + /hs-tendermint-client;
    nameservice = root + /hs-abci-docs/nameservice;
    simple-storage = root + /hs-abci-docs/simple-storage;
  };

  repos = {
    avl-auth = pkgs.fetchFromGitHub {
      owner  = "oscoin";
      repo   = "avl-auth";
      rev    = "dfc468845a82cdd7d759943b20853999bc026505";
      sha256 = "005j98hmzzh9ybd8wb073i47nwvv1hfh844vv4kflba3m8d75d80";
    };
    http2-grpc-haskell = pkgs.fetchFromGitHub {
      owner  = "haskell-grpc-native";
      repo   = "http2-grpc-haskell";
      rev    = "496e92bc967eff02ac3698ba12ba2dfe38bc8b74";
      sha256 = "199nz6dpqlzg9jyc0kq1har0l2zididpi2wkriai6cn91s7fc3my";
    };
    proto3-suite = pkgs.fetchFromGitHub {
      owner  = "awakesecurity";
      repo   = "proto3-suite";
      rev    = "45950a3860cbcb3f3177e9725dbdf460d6da9d45";
      sha256 = "1fm0a5i9q9p393c9if6n6nz0q7di0p1fjx262fyj7j20nnl3f9i3";
    };
    proto3-wire = pkgs.fetchFromGitHub {
      owner  = "awakesecurity";
      repo   = "proto3-wire";
      rev    = "5df56fe1ad26a18b1dfbb2a5b8d35b4c1ad63f53";
      sha256 = "1d2ir9ds4vawrn6lkxqgyw9zg8h2l4d6m8ihhy6znjllh12fmjyp";
    };
  };

  repoPackages = {
    inherit (repos) avl-auth proto3-suite proto3-wire;
  };

  extra-build-inputs = with pkgs; {
    hs-abci-sdk = [protobuf];
    hs-abci-types = [protobuf];
    hs-iavl-client = [protobuf];
    simple-storage = [protobuf];
  };

  addBuildInputs = inputs: { buildInputs ? [], ... }: { buildInputs = inputs ++ buildInputs; };

  hackageOverrides = self: super: {
    ghc-tcplugins-extra = self.callHackage "ghc-tcplugins-extra" "0.3.2" {};

    http2-client = pkgs.haskell.lib.doJailbreak super.http2-client;
    http2-client-grpc = self.callCabal2nix "http2-client-grpc" (repos.http2-grpc-haskell + /http2-client-grpc) {};
    http2-grpc-proto-lens = self.callCabal2nix "http2-grpc-proto-lens" (repos.http2-grpc-haskell + /http2-grpc-proto-lens) {};

    polysemy = self.callHackage "polysemy" "1.3.0.0" {};
    polysemy-plugin = self.callHackage "polysemy-plugin" "0.2.5.0" {};
    polysemy-zoo = self.callHackage "polysemy-zoo" "0.7.0.0" {};

    prometheus = self.callHackageDirect {
      pkg = "prometheus";
      ver = "2.1.3";
      sha256 = "04w3cm6r6dh284mg1lpzj4sl6d30ap3idkkdjzck3vcy5p788554";
    } {};
  };

  localOverrides = self: super:
    builtins.mapAttrs (name: path: (self.callCabal2nix name (gitignoreSource path) {})) packages;

  repoOverrides = self: super:
    builtins.mapAttrs (name: path: (self.callCabal2nix name path {})) repoPackages;

  overrides = self: super:
    let allOverrides =
          hackageOverrides self super
          // repoOverrides self super
          // localOverrides self super;
    in
      builtins.mapAttrs (name: pkg: pkg.overrideAttrs (addBuildInputs (extra-build-inputs.${name} or []))) allOverrides;

  # TODO: figure out why running tests on mac causes builds to hang _after_ running the tests
  keplerTests = pkg: args: if pkgs.stdenv.isDarwin then pkgs.haskell.lib.dontCheck pkg else keplerTests' pkg args;

  keplerTests' = pkg: { runIavl ? false, runABCI ? null, runTendermint ? null }: pkgs.lib.overrideDerivation pkg (drv:
    let
      iavlScript = ''
        ${iavl}/bin/iavlserver -db-name "test" -datadir "." -grpc-endpoint "0.0.0.0:8090" -gateway-endpoint "0.0.0.0:8091" &
        sleep 3
      '';
      abciScript = ''
        ${runABCI} &
        sleep 3
      '';
      tendermintScript = ''
        ${tendermint}/bin/tendermint init --home $TMPDIR
        ${tendermint}/bin/tendermint node --home $TMPDIR --proxy_app=${runTendermint} &
        sleep 3
      '';
    in {
      checkPhase = pkgs.lib.concatStrings [
        (pkgs.lib.optionalString runIavl iavlScript)
        (pkgs.lib.optionalString (runABCI != null) abciScript)
        (pkgs.lib.optionalString (runTendermint != null) tendermintScript)
        drv.checkPhase
      ];
    });

  overlay = self: super: {
    inherit iavl tendermint;

    haskellPackages =
      super.haskellPackages.override (old: {
        overrides = pkgs.lib.foldr pkgs.lib.composeExtensions (old.overrides or (_: _: {})) [
          overrides
          (self: super: with pkgs.haskell.lib; {
            http2-client = unmarkBroken super.http2-client;
            parameterized = dontCheck (unmarkBroken super.parameterized);

            # https://github.com/NixOS/nixpkgs/pull/82562
            secp256k1 = null;
            secp256k1-haskell = addPkgconfigDepend (self.callHackage "secp256k1-haskell" "0.1.8" {}) pkgs.secp256k1;

            avl-auth = dontCheck super.avl-auth;  # https://github.com/haskell-haskey/xxhash-ffi/issues/2
            bloodhound = doJailbreak (unmarkBroken super.bloodhound); # tight bounds
            katip-elasticsearch = dontCheck (unmarkBroken super.katip-elasticsearch); # needs elastic-search for tests
            proto3-suite = dontCheck super.proto3-suite; # needs old 'tasty'

            hs-tendermint-client = dontCheck super.hs-tendermint-client; # last test fails frequently
            hs-iavl-client = keplerTests super.hs-iavl-client { runIavl = true; };
            hs-abci-sdk = keplerTests super.hs-abci-sdk { runIavl = true; };

            simple-storage = keplerTests super.simple-storage {
              runIavl = true;
              runABCI = "IAVL_HOST=localhost IAVL_PORT=8090 dist/build/simple-storage/simple-storage";
              runTendermint= "tcp://localhost:26658";
            };

            nameservice = dontCheck super.nameservice;
          }
        )
      ];
    });
  };

  overlays = [overlay];

in rec {
  inherit pkgs overlays;

  buildInputs = {
    inherit (pkgs) iavl protobuf tendermint;
    inherit (pkgs.haskellPackages) cabal-install ghcid hlint stack stylish-haskell weeder;
  };

  keplerPackages = keplerPackages' pkgs.haskellPackages;
  keplerPackages' = p: with p; {
    inherit
      hs-abci-extra
      hs-abci-sdk
      hs-abci-server
      hs-abci-test-utils
      hs-abci-types
      hs-iavl-client
      hs-tendermint-client
      nameservice
      simple-storage
    ;
  };
}
