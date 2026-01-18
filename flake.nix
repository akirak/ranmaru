{
  inputs = {
    nixpkgs.url = "github:nix-ocaml/nix-overlays";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    extra-substituters = [
      "https://akirak.cachix.org"
    ];
    extra-trusted-public-keys = [
      "akirak.cachix.org-1:WJrEMdV1dYyALkOdp/kAECVZ6nAODY5URN05ITFHC+M="
    ];
  };

  outputs =
    {
      nixpkgs,
      self,
      ...
    }@inputs:
    let
      eachSystem =
        f:
        nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed (
          system:
          f (
            nixpkgs.legacyPackages.${system}.extend (
              _self: super: {
                # You can set the OCaml version to a particular release. Also, you
                # may have to pin some packages to a particular revision if the
                # devshell fail to build. This should be resolved in the upstream.
                ocamlPackages = super.ocaml-ng.ocamlPackages_latest;
              }
            )
          )
        );

      treefmtEval = eachSystem (
        pkgs:
        inputs.treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";

          # You can add formatters for your languages.
          # See https://github.com/numtide/treefmt-nix#supported-programs

          programs.ocamlformat.enable = true;
          programs.nixfmt.enable = true;
          programs.actionlint.enable = true;
        }
      );
    in
    {
      packages = eachSystem (pkgs: rec {
        default = ranmaru;

        ranmaru = pkgs.ocamlPackages.buildDunePackage {
          pname = "ranmaru";
          version = "0";
          duneVersion = "3";
          src = ./.;
          buildInputs = [ pkgs.ocamlPackages.ocaml-syntax-shims ];
          propagatedBuildInputs = with pkgs.ocamlPackages; [
            eio
            eio_main
            jsonrpc
            lsp
            kcas
            kcas_data
            cmdliner
          ];
          checkInputs = with pkgs.ocamlPackages; [
            alcotest
          ];
          doCheck = true;
        };
      });

      devShells = eachSystem (pkgs: {
        default = pkgs.mkShell {
          inputsFrom = with self.packages.${pkgs.system}; [
            ranmaru
          ];
          packages = (
            with pkgs.ocamlPackages;
            [
              ocaml-lsp
              ocamlformat
              ocp-indent
              utop
            ]
          );
        };
      });

      formatter = eachSystem (pkgs: treefmtEval.${pkgs.system}.config.build.wrapper);

      checks = eachSystem (pkgs: {
        format = treefmtEval.${pkgs.system}.config.build.check self;
        inherit (self.packages.${pkgs.system}) ranmaru;
      });
    };
}
