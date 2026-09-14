{
  description = "Lyceum staging host with isolated Aristos Caddy service";

  inputs = {
    lyceum.url = "path:./lyceum-website";
  };

  outputs = { self, lyceum }:
    let
      deployedLyceum = builtins.storePath "/nix/store/an10f714yzyinkc8aiq1xn4ri2cl5nf9-lyceum-0.1.0";
      deployedAdmin = builtins.storePath "/nix/store/w751ss0df1pc7bn4nrb1jyz4jzd256s5-lyceum-admin-0.1.0";

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
          # Preserve the exact reader and admin builds from the existing host
          # while extending its stale source configuration.
          services.lyceum.package = deployedLyceum;

          systemd.services.lyceum-admin = {
            description = "Lyceum Admin Server";
            after = [ "network.target" "lyceum.service" ];
            wantedBy = [ "multi-user.target" ];
            environment.ADMIN_PORT = "8081";
            serviceConfig = {
              Type = "simple";
              ExecStart = "${deployedAdmin}/bin/lyceum-admin";
              WorkingDirectory = "/var/lib/lyceum/data";
              EnvironmentFile = "/var/lib/lyceum/admin.env";
              User = "lyceum";
              Group = "lyceum";
              Restart = "always";
              RestartSec = 5;
              ReadWritePaths = [ "/var/lib/lyceum/data" ];
              NoNewPrivileges = true;
              PrivateTmp = true;
              ProtectHome = true;
              ProtectSystem = "strict";
            };
          };

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

          # Keep every pre-existing staging route explicit. The public Caddy
          # process remains the sole TLS owner for ports 80 and 443.
          services.caddy.virtualHosts = {
            "admin.demo.lyceum.quest".extraConfig = ''
              reverse_proxy localhost:8081
            '';
            "conllu.lyceum.quest".extraConfig = ''
              root * /var/www/conllu-viz
              encode zstd gzip
              try_files {path} /index.html
              file_server
            '';
            "aristos.lyceum.quest".extraConfig = ''
              reverse_proxy 127.0.0.1:8092
            '';
          };
        };
    in {
      nixosConfigurations.staging =
        lyceum.nixosConfigurations.staging.extendModules {
          modules = [ aristosModule ];
        };
    };
}
