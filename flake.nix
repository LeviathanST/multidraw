{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    devShells.${system} = {
      default = pkgs.mkShellNoCC { packages = [ pkgs.zig_0_16 pkgs.nodejs_24 ]; };
      client  = pkgs.mkShellNoCC { packages = with pkgs; [
        nodejs_24
        svelte-language-server
        tailwindcss-language-server
        typescript-language-server
        vscode-langservers-extracted
        emmet-language-server
      ]; };   # nix develop .#client
      server  = pkgs.mkShellNoCC { packages = [ pkgs.zig_0_16 pkgs.zls_0_16 ]; };  # nix develop .#server
    };
  };
}
