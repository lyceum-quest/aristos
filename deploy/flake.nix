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

            :8092 {
              root * /var/www/aristos
              encode zstd gzip
              try_files {path} /index.html
              file_server
            }
          '';
        in {
          users.users.root.openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG2UytIqUbPYXbsjjnIIEE/F0nHNm7AhVjz7ITxjIMNb github-actions-deploy"
          ];

          swapDevices = [{
            device = "/var/lib/swapfile";
            size = 4096;
          }];

          users.groups.paseo = {};
          users.users.paseo = {
            isSystemUser = true;
            group = "paseo";
            home = "/var/lib/paseo";
            createHome = true;
            shell = pkgs.bashInteractive;
          };

          systemd.services.paseo-install = {
            description = "Install pinned Paseo and Pi releases";
            after = [ "network-online.target" ];
            before = [ "paseo.service" ];
            wants = [ "network-online.target" ];
            path = [ pkgs.nodejs_22 ];
            script = ''
              set -eu
              paseo_version="$(/var/lib/paseo/npm/bin/paseo --version 2>/dev/null || true)"
              pi_version="$(/var/lib/paseo/npm/bin/pi --version 2>/dev/null || true)"
              if [ "$paseo_version" != "0.8.0" ] || [ "$pi_version" != "0.85.1" ]; then
                npm install --global --prefix /var/lib/paseo/npm \
                  @getpaseo/cli@0.8.0 \
                  @earendil-works/pi-coding-agent@0.85.1
              fi
            '';
            serviceConfig = {
              Type = "oneshot";
              User = "paseo";
              Group = "paseo";
              StateDirectory = "paseo";
              NoNewPrivileges = true;
              PrivateTmp = true;
              ProtectHome = true;
              ProtectSystem = "full";
              ReadWritePaths = [ "/var/lib/paseo" ];
            };
          };

          systemd.services.paseo = {
            description = "Paseo coding agent server";
            after = [ "network-online.target" "paseo-install.service" ];
            requires = [ "paseo-install.service" ];
            wants = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];
            environment = {
              HOME = "/var/lib/paseo";
              PASEO_HOME = "/var/lib/paseo/.paseo";
              PASEO_HOSTNAMES = "paseo.lyceum.quest";
              PASEO_LISTEN = "127.0.0.1:6767";
              PASEO_RELAY_ENABLED = "false";
              PASEO_WEB_UI_ENABLED = "true";
              PATH = lib.mkForce "/var/lib/paseo/npm/bin:${lib.makeBinPath [
                pkgs.bashInteractive
                pkgs.coreutils
                pkgs.curl
                pkgs.fd
                pkgs.findutils
                pkgs.gawk
                pkgs.git
                pkgs.gnugrep
                pkgs.gnused
                pkgs.jq
                pkgs.nix
                pkgs.nodejs_22
                pkgs.openssh
                pkgs.ripgrep
                pkgs.rsync
              ]}";
            };
            serviceConfig = {
              Type = "simple";
              ExecStart = "/var/lib/paseo/npm/bin/paseo daemon start";
              EnvironmentFile = "/var/lib/paseo/paseo.env";
              User = "paseo";
              Group = "paseo";
              StateDirectory = "paseo";
              WorkingDirectory = "/var/lib/paseo";
              Restart = "on-failure";
              RestartSec = 5;
              NoNewPrivileges = true;
              PrivateDevices = true;
              ProtectHome = true;
              ProtectSystem = "full";
              ReadWritePaths = [ "/var/lib/paseo" ];
            };
          };

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
            "paseo.lyceum.quest".extraConfig = ''
              reverse_proxy 127.0.0.1:6767
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
