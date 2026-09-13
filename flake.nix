{
  description = "Aristos Ancient Greek reading workspace deployment";

  inputs = {
    lyceum.url = "path:/home/blu/src/greek/lyceum/website";
    elmNixpkgs.url = "github:NixOS/nixpkgs/eaad089433ca2bb662274377d33df3d0e51ef28b";
  };

  outputs = { self, lyceum, elmNixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = elmNixpkgs.legacyPackages.${system};
      aristosModule = { config, lib, pkgs, ... }:
        let
          aristosCaddyfile = pkgs.writeText "aristos-Caddyfile" ''
            {
              admin off
              auto_https off
            }

            http://127.0.0.1:8092 {
              root * /var/www/aristos
              encode zstd gzip
              try_files {path} /index.html
              file_server
            }
          '';
        in {
          systemd.services.aristos-caddy = {
            description = "Aristos static site Caddy server";
            after = [ "network.target" ];
            wantedBy = [ "multi-user.target" ];

            environment = {
              HOME = "/var/lib/aristos-caddy";
              XDG_CONFIG_HOME = "/var/lib/aristos-caddy/config";
              XDG_DATA_HOME = "/var/lib/aristos-caddy/data";
            };

            serviceConfig = {
              Type = "notify";
              ExecStart = "${pkgs.caddy}/bin/caddy run --config ${aristosCaddyfile} --adapter caddyfile";
              ExecReload = "${pkgs.caddy}/bin/caddy reload --config ${aristosCaddyfile} --adapter caddyfile --force";
              User = "caddy";
              Group = "caddy";
              Restart = "on-failure";
              RestartSec = 5;
              StateDirectory = "aristos-caddy";
              NoNewPrivileges = true;
              PrivateDevices = true;
              PrivateTmp = true;
              ProtectHome = true;
              ProtectSystem = "strict";
              ReadOnlyPaths = [ "/var/www/aristos" ];
            };
          };

          services.caddy.virtualHosts."aristos.lyceum.quest" = {
            extraConfig = ''
              reverse_proxy 127.0.0.1:8092
            '';
          };
        };
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.elmPackages.elm ];
      };

      nixosConfigurations.staging =
        lyceum.nixosConfigurations.staging.extendModules {
          modules = [ aristosModule ];
        };
    };
}
