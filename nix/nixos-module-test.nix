{ sources ? import ./sources.nix
, pkgs ? import ./pkgs.nix { inherit sources; }
}:
let
  bevel-production = import (./nixos-module.nix) {
    envname = "production";
    bevelReleasePackages = pkgs.bevelReleasePackages;
  };
  home-manager = import (pkgs.home-manager.src + "/nixos/default.nix");
  port = 8001;
in
pkgs.nixosTest (
  { lib, pkgs, ... }: {
    name = "bevel-module-test";
    nodes = {
      server = {
        imports = [
          bevel-production
        ];
        services.bevel.production = {
          enable = true;
          api-server = {
            enable = true;
            inherit port;
          };
        };
      };
      client = {
        imports = [
          home-manager
        ];
        users.users.testuser.isNormalUser = true;
        home-manager = {
          useGlobalPkgs = true;
          users.testuser = { pkgs, ... }: {
            imports = [
              ./home-manager-module.nix
            ];
            home.packages = with pkgs; [
              sqlite
            ];
            programs.bash.enable = true;
            programs.zsh.enable = true;
            xdg.enable = true;
            programs.bevel = {
              enable = true;
              bevelReleasePackages = pkgs.bevelReleasePackages;
              harness = {
                bash = {
                  enable = true;
                  bindings = true;
                };
                zsh = {
                  enable = true;
                  bindings = true;
                };
              };
              sync = {
                enable = true;
                server-url = "server:${builtins.toString port}";
                username = "testuser";
                password = "testpassword";
              };
            };
          };
        };
      };
    };
    testScript = ''
      from shlex import quote

      server.start()
      client.start()
      server.wait_for_unit("multi-user.target")
      client.wait_for_unit("multi-user.target")

      server.wait_for_open_port(${builtins.toString port})
      client.succeed("curl server:${builtins.toString port}")

      client.wait_for_unit("home-manager-testuser.service")


      def su(user, cmd):
          return f"su - {user} -c {quote(cmd)}"


      client.succeed(su("testuser", "cat ~/.config/bevel/config.yaml"))

      client.succeed(su("testuser", "bevel register"))
      client.succeed(su("testuser", "bevel login"))
      client.succeed(su("testuser", "bevel sync"))
    '';
  }
)
