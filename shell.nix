{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  packages = with pkgs; [
    shellcheck
    curl
    file
    gnugrep
    gnused
    git
  ];
}
