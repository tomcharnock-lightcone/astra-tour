{
  description = "A hands-on tour of astra-tools: the shell it runs in";

  # The system's nixpkgs (the flake registry's), so that no download is needed where it is
  # already in the store. `nix flake lock` pins it the first time.
  inputs.nixpkgs.url = "nixpkgs";

  outputs = { nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      each = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = each (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [ python314 uv git jq perl coreutils gnused gnugrep diffutils findutils ];
          # uv builds astra-tools' environment on this Python, and never downloads one.
          UV_PYTHON = "${pkgs.python314}/bin/python3.14";
          UV_PYTHON_DOWNLOADS = "never";
          # Wheels with compiled code (rapidfuzz, pydantic-core) need the C++ runtime and zlib,
          # which NixOS keeps out of the usual places.
          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib pkgs.zlib ];
        };
      });
    };
}
