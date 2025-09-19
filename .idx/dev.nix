{ pkgs, ... }: {
  channel = "stable-23.11";
  inputs = {
    # If you want to use the latest Flutter stable version, you can use the `flutter-stable` package from `Nix unstable`.
    # More information about this can be found here: https://search.nixos.org/packages?channel=unstable&show=flutter-stable&type=packages&query=flutter-stable
    nixpkgs-unstable = {
      type = "NixPkgs";
      url = "https://nixos.org/channels/nixpkgs-unstable";
    };
  };
  packages = [
    # To use the latest Flutter version, you would replace `pkgs.flutter` with `inputs.nixpkgs-unstable.flutter-stable`.
    # Don't forget to remove `nixpkgs-unstable` from the `inputs` if you are not using it.
    pkgs.flutter
    pkgs.dart
    pkgs.cmake
  ];
  extensions = [
    "dart-code.flutter"
    "dart-code.dart-code"
  ];

  idx.workspace.onStart = "flutter doctor";
  idx.previews.enable = true;
}
