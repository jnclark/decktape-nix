{
  description = "A Nix Flake for DeckTape (+ extras)";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-23.11;
    decktape-src = {
      url = github:astefanutti/decktape;
      flake = false;
    };
    revealjs-src = {
      url = github:hakimel/reveal.js;
      flake = false;
    };
  };

  outputs = { self, nixpkgs, decktape-src, revealjs-src, ... }:
    let
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
      systems = [ "x86_64-linux" "aarch64-linux" ];
    in
    {
      overlays.default = final: prev: {
        decktape = prev.buildNpmPackage {
          name = "decktape";
          src = decktape-src;
          npmDepsHash = "sha256-dZAt/ffLy+qzG3gVk+nGujFnx+G2yeGMEmrhRm1JoUs=";
          npmPackFlags = [ "--ignore-scripts" ];
          postPatch = ''
            # Substitute in npm-shrinkwrap for package-lock
            cp npm-shrinkwrap.json package-lock.json
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
            printf ${self.inputs.revealjs-src}
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
      apps = forAllSystems (system: {
        decktape = {
          type = "app";
          name = "decktape";
          program = "${self.packages.${system}.decktape}/bin/decktape";
        };
        default = self.apps.${system}.decktape;
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
