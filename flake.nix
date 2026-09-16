{
  description = "Report-first NixOS health checker";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forEachSystem = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));
    in {
      packages = forEachSystem (pkgs: {
        default = pkgs.stdenvNoCC.mkDerivation {
          pname = "nixos-doctor";
          version = "1.0.0";
          src = ./.;
          dontBuild = true;
          installPhase = ''
            mkdir -p $out/libexec/nixos-doctor/checks $out/bin $out/share/nixos-doctor
            cp nixos-doctor tui.sh bundle.sh backup.sh $out/libexec/nixos-doctor/
            cp checks/*.sh $out/libexec/nixos-doctor/checks/
            cp -r docs $out/share/nixos-doctor/
            chmod +x $out/libexec/nixos-doctor/*.sh
            ln -s $out/libexec/nixos-doctor/nixos-doctor $out/bin/nixos-doctor
          '';
        };
      });
      checks = forEachSystem (pkgs: {
        syntax = pkgs.runCommand "nixos-doctor-syntax" { nativeBuildInputs = [ pkgs.bash ]; } ''
          for f in ${self}/nixos-doctor ${self}/tui.sh ${self}/bundle.sh ${self}/tests.sh ${self}/checks/*.sh; do bash -n "$f"; done
          touch $out
        '';
        shellcheck = pkgs.runCommand "nixos-doctor-shellcheck" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
          shellcheck -S warning -s bash ${self}/nixos-doctor ${self}/tui.sh ${self}/bundle.sh ${self}/tests.sh ${self}/checks/*.sh
          touch $out
        '';
        schema = pkgs.runCommand "nixos-doctor-json-schema" {
          nativeBuildInputs = [ pkgs.python3Packages.jsonschema pkgs.python3 ];
        } ''
          python3 -c 'import json,jsonschema; [jsonschema.Draft202012Validator.check_schema(json.load(open(p))) for p in ("${self}/docs/json-schema-v1.json", "${self}/docs/json-schema-v2.json")]'
          touch $out
        '';
      });
      apps = forEachSystem (pkgs: {
        default = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/nixos-doctor";
          meta = { description = "Report-first NixOS health checker"; };
        };
      });
    };
}
