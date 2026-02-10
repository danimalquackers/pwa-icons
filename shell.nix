{
  pkgs ? import <nixpkgs> { },
}:
with pkgs;

mkShell {
  buildInputs = [
    # Nix LSP
    nil

    # Webpage analysis and parsing tools
    file
    gnugrep
    gnused
    coreutils

    # Tools for fetching webpages and icons
    curl
    cacert
  ];
}
