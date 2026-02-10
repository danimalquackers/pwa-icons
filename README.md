# PWA Icon Downloader

A lightweight, robust tool for fetching high-quality icons for web applications and PWAs. Designed for use with **Nix** and **Home Manager**.

## Features

- **Fallback Strategy**: 
  1. **PWA Manifest**: Parses `manifest.json` for themed and high-res icons.
  2. **HTML Scraping**: Finds icons via `<link rel="icon">`, `shortcut icon`, and `apple-touch-icon`.
  3. **Direct Fetch**: Attempts typical `/favicon.ico` locations.
  4. **Google S2 Fallback**: Reliable final fallback using Google's favicon service.
- **Nix Integration**:
  - **Home Manager Module**: Injects a `downloadWebAppIcon` helper.
  - **Nixpkgs Overlay**: Accessible as `pkgs.downloadWebAppIcon`.

## Installation

### Using Nix Flakes

Add this to your `flake.nix` inputs:

```nix
inputs.pwa-icons.url = "github:danimalquackers/pwa-icons";
```

## Usage

### Home Manager

Import the module and use the `downloadWebAppIcon` helper in your desktop items:

```nix
{ pkgs, pwa-icons, ... }: {
  imports = [ pwa-icons.homeManagerModules.default ];

  home.packages = [
    (pkgs.makeDesktopItem {
      name = "YouTube Music";
      exec = "firefox ...";
      icon = pwa-icons.downloadWebAppIcon {
        domain = "music.youtube.com";
        hash = lib.fakeHash; # Nix will provide the correct hash on first run
      };
    })
  ];
}
```

### Nixpkgs Overlay

```nix
{ pkgs, pwa-icons, ... }: {
  nixpkgs.overlays = [ pwa-icons.overlays.default ];

  # Use via pkgs
  icon = pkgs.downloadWebAppIcon {
    domain = "music.youtube.com";
    hash = lib.fakeHash;
  };
}
```
