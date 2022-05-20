{
  description = "SF Eng Challenge";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          # Necessary for materialize
          config.allowUnfree = true;
        };
      in {
        devShell = pkgs.mkShell {
          buildInputs = [ pkgs.nushell pkgs.postgresql_14 ];
        };
        arion-pkgs = pkgs;
        arion-compose = { pkgs, ... }: {
          config.project.name = "sf-eng-challenge";
          config.services = {
            postgres = {
              service.capabilities.SYS_ADMIN = true;
              service.useHostStore = true;
              service.ports = [ "5432:5432" ];

              nixos.useSystemd = true;
              nixos.configuration = { pkgs, config, ... }: {
                services.postgresql.enable = true;
                services.postgresql.package = pkgs.postgresql_14;
                # Wildly secure
                services.postgresql.authentication = ''
                  local all all trust
                  host all all 0.0.0.0/0 trust
                  host all all ::0/0 trust
                '';
                services.postgresql.settings = {
                  listen_addresses = pkgs.lib.mkForce "*";
                  wal_level = "logical";
                };
                services.postgresql.initialScript = ./init.sql;
              };
            };
            materialize = {
              service.image = "materialize/materialized:v0.26.1";
              service.restart = "unless-stopped";
              service.ports = [ "6875:6875" ];
            };
            materialize_init = {
              service.useHostStore = true;
              service.depends_on = [ "materialize" "postgres" ];
              service.command = [
                "${pkgs.bash}/bin/bash"
                "-c"
                ''
                  RETRIES=10

                  until ${pkgs.postgresql_14}/bin/psql -h postgres -U postgres -c 'select id from api_v1.users limit 1' || (( RETRIES <= 0 )); do
                    echo "Waiting for postgres server, $$((RETRIES--)) remaining attempts..."
                    ${pkgs.coreutils}/bin/sleep 1
                  done
                  until ${pkgs.postgresql_14}/bin/psql -h materialize -U materialize -p 6875 -d materialize -c 'select 1' || (( RETRIES <= 0 )); do
                    echo "Waiting for materialize server, $$((RETRIES--)) remaining attempts..."
                    ${pkgs.coreutils}/bin/sleep 1
                  done

                  ${pkgs.jq}/bin/jq -c ".[]" users.json > postgres_users.json
                  ${pkgs.jq}/bin/jq -c ".[]" opportunities.json > postgres_opportunities.json

                  ${pkgs.postgresql_14}/bin/psql -h materialize -U materialize -p 6875 -d materialize -f ${./materialize.sql}
                  ${pkgs.postgresql_14}/bin/psql -h postgres -U postgres -f ${./postgres_sink.sql}
                  ${pkgs.postgresql_14}/bin/psql -h postgres -U postgres -f ${./copy_data.sql}
                ''
              ];
              service.volumes = [
                "./users.json:/users.json"
                "./opportunities.json:/opportunities.json"
              ];
            };
            graphile = {
              service.image = "graphile/postgraphile:4";
              service.ports = [ "5433:5433" ];
              service.depends_on = [ "materialize_init" ];
              service.command = [
                "--connection" "postgres://postgres@postgres:5432/postgres"
                "--port" "5433"
                "--schema" "api_v1"
                "--enhance-graphiql"
                "--retry-on-init-fail"
                # Unfortunately this needs superuser privileges
                "--watch"
              ];
            };
          };
        };
      });
}
