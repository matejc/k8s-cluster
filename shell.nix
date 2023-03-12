{ pkgs ? import <nixpkgs> {} }:
with pkgs;
mkShell {
  nativeBuildInputs = [ cloudflared kubectl yq-go k9s git-crypt ];
}
