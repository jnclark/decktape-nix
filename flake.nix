{
  description = "A Nix Flake for DeckTape (+ extras)";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-24.11;
  };

  outputs = { self, nixpkgs, ... }:
    let
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
      systems = [ "x86_64-linux" "aarch64-linux" ];
      decktapeVersion = "3.14.0";
      revealjs-src = nixpkgs.legacyPackages.x86_64-linux.fetchFromGitHub {
        owner = "hakimel";
        repo = "reveal.js";
        rev = "5.1.0";
        sha256 = "sha256-L6KVBw20K67lHT07Ws+ZC2DwdURahqyuyjAaK0kTgN0=";
      };
    in
    {
      overlays.default = final: prev: {
        decktape = prev.buildNpmPackage {
          pname = "decktape";
          version = decktapeVersion;
          src = prev.fetchFromGitHub {
            owner = "astefanutti";
            repo = "decktape";
            rev = "v${decktapeVersion}";
            sha256 = "sha256-V7JoYtwP7iQYFi/WhFpkELs7mNKF6CqrMyjWhxLkcTA=";
          };
          npmDepsHash = "sha256-rahrIhB0GhqvzN2Vu6137Cywr19aQ70gVbNSSYzFD+s=";
          npmPackFlags = [ "--ignore-scripts" ];
          postPatch = ''
            # Skip download of Chrome, as we will wrap in our own
            export PUPPETEER_SKIP_DOWNLOAD=1
          '';
          dontNpmBuild = true;
          postFixup = ''
            wrapProgram $out/bin/decktape \
              --add-flags "--chrome-path ${prev.ungoogled-chromium}/bin/chromium" \
              --set PATH ${prev.lib.makeBinPath [
                prev.ungoogled-chromium
              ]}
          '';
          meta = with prev.lib; {
            description = "PDF exporter for HTML presentations";
            homepage = "https://github.com/astefanutti/decktape";
            license = licenses.mit;
          };
        };
        revealjs-source-path-util = prev.writeShellApplication {
          # A small utility to return the path of the revealjs-src
          # within the nix store for use as org-reveal-root in
          # org/ox-reveal
          name = "revealjs-source-store-path";
          runtimeInputs = [ ];
          text = ''
            printf ${revealjs-src}
          '';
        };
        mathjax-path-util = prev.writeShellApplication {
          # A small utility to return the local path to mathjax
          # within the nix store for use as org-reveal-mathjax-url in
          # org/ox-reveal
          name = "mathjax-store-path";
          runtimeInputs = [ ];
          text = ''
            printf ${prev.nodePackages.mathjax}
          '';
        };
        org-reveal-utils = prev.symlinkJoin {
          name = "org-reveal-utils";
          paths = [
            final.revealjs-source-path-util
            final.mathjax-path-util
          ];
        };
      };
      packages = forAllSystems (system: {
        decktape = (import nixpkgs { inherit system; overlays = [ self.overlays.default ]; }).decktape;
        org-reveal-utils = (import nixpkgs { inherit system; overlays = [ self.overlays.default ]; }).org-reveal-utils;
        default = self.packages.${system}.decktape;
      });
      checks = forAllSystems (system: {
        build = self.packages.${system}.default;
        test = with import (nixpkgs + "/nixos/lib/testing-python.nix")
          {
            inherit system;
          };
          makeTest {
            name = "run-decktape-nix-${system}";
            nodes = {
              client = { ... }: {
                imports = [ self.nixosModules.decktape-nix ];
                nixpkgs.overlays = [ self.overlays.default ];
              };
            };
            testScript = ''
              start_all()
              client.wait_for_unit("multi-user.target")
              client.succeed("decktape version")
              client.succeed("revealjs-source-store-path")
              client.succeed("mathjax-store-path")
            '';
          };
      });
      nixosModules.decktape-nix =
        { pkgs, ... }:
        {
          nixpkgs.overlays = [ self.overlays.default ];
          environment.systemPackages = [ pkgs.decktape pkgs.org-reveal-utils ];
        };
      hydraJobs = {
        packages = self.packages;
        checks = self.checks;
      };
      formatter = forAllSystems (system:
        (import nixpkgs { inherit system; }).nixpkgs-fmt);
    };
}
