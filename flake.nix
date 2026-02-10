{
  description = "A tool to download PWA icons for web applications";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }@inputs:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: import nixpkgs { inherit system; };

      # The core fetcher logic defined as a function of pkgs
      mkDownloadWebAppIcon =
        pkgs:
        {
          domain,
          hash ? "",
          sha256 ? "",
        }:
        let
          # Support both hash and sha256 parameters like other nix fetchers
          finalHash = if hash != "" then hash else sha256;

          # We need the downloader as a dependency
          downloader = self.packages.${pkgs.system}.default;
        in
        pkgs.stdenv.mkDerivation {
          name = "${builtins.replaceStrings [ ":" "/" " " ] [ "_" "_" "_" ] domain}-icon.ico";

          nativeBuildInputs = with pkgs; [
            # Webpage analysis and parsing tools
            file
            gnugrep
            gnused
            coreutils

            # Tools for fetching webpages and icons
            curl
            cacert
          ];

          # This makes it a Fixed-Output Derivation (FOD), which has network access
          outputHash = finalHash;
          outputHashAlgo = if finalHash == "" then null else null; # Nix handles this if hash is provided
          outputHashMode = "flat";

          buildCommand = ''
            ${downloader}/bin/pwa-icons "${domain}" "$out"
          '';
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.writeShellApplication {
            name = "pwa-icons";
            runtimeInputs = with pkgs; [
              # Webpage analysis and parsing tools
              file
              gnugrep
              gnused
              coreutils

              # Tools for fetching webpages and icons
              curl
              cacert
            ];
            text = builtins.readFile ./download_icons.sh;
          };
        }
      );

      # Expose the fetcher in lib
      lib = {
        inherit mkDownloadWebAppIcon;
      };

      # Provide an overlay to add it to pkgs
      overlays.pwa-icons = final: prev: {
        downloadWebAppIcon = mkDownloadWebAppIcon final;
      };

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              self.packages.${system}.default
              shellcheck
            ];
          };
        }
      );

      homeManagerModules.pwa-icons =
        { pkgs, ... }:
        {
          # Inject the helper into module arguments
          _module.args = {
            downloadWebAppIcon = mkDownloadWebAppIcon pkgs;
          };
        };
    };
}
