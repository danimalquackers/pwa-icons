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
            curl
            file
            gnugrep
            gnused
            coreutils
          ];

          # This makes it a Fixed-Output Derivation (FOD), which has network access
          outputHash = finalHash;
          outputHashAlgo = if finalHash == "" then null else null; # Nix handles this if hash is provided
          outputHashMode = "flat";

          # Run the script. We pass "." as the output directory.
          # The script will create a .ico file, which we then move to $out.
          buildCommand = ''
            export HOME=$TMPDIR
            ${downloader}/bin/pwa-icon-downloader "${domain}" .
            # Find the generated ico file and move it to the output path
            mv *.ico "$out"
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
            name = "pwa-icon-downloader";
            runtimeInputs = with pkgs; [
              curl
              coreutils
              findutils
              file
              gnused
              gnugrep
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
      overlays.default = final: prev: {
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

            languages.sh.enable = true;
          };
        }
      );

      homeManagerModules.default =
        { pkgs, ... }:
        {
          # Inject the helper into module arguments
          _module.args = {
            downloadWebAppIcon = mkDownloadWebAppIcon pkgs;
          };
        };
    };
}
