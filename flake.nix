{
  description = "Dev environment for Claude Code";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils }:
  utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      postgres = pkgs.postgresql_16;
      claude-code = pkgs.buildNpmPackage {
          pname = "claude-code";
          version = "latest"; # Or specify a version like "0.2.9"

          src = pkgs.fetchurl {
            url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-0.2.29.tgz";
            hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
          };

          npmDepsHash = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";
          dontBuild = true;
        };

      pgInit = pkgs.writeShellScriptBin "pg-init" ''
        set -euo pipefail
        mkdir -p "$PGDATA" "$PGHOST" "$PG_LOG"
        if [ ! -f "$PGDATA/PG_VERSION" ]; then
          echo "Initialising cluster at $PGDATA"
          ${postgres}/bin/initdb -D "$PGDATA" \
            --auth=trust --no-locale --encoding=UTF8 -U "$PGUSER" >/dev/null
        fi
        if ! ${postgres}/bin/pg_ctl -D "$PGDATA" status >/dev/null 2>&1; then
          ${postgres}/bin/pg_ctl -D "$PGDATA" \
            -l "$PG_LOG/postgres.log" \
            -o "-k $PGHOST -h '''" \
            start
          STARTED_HERE=1
        else
          STARTED_HERE=0
        fi
        if ! ${postgres}/bin/psql -lqt | cut -d\| -f1 | grep -qw "$PGDATABASE"; then
          ${postgres}/bin/createdb "$PGDATABASE"
        fi
        mkdir -p "$LUCIANA_ROOT/config/backend"
        echo "postgresql:///$PGDATABASE?host=$PGHOST" \
          > "$LUCIANA_ROOT/config/backend/db-url"
        if [ "$STARTED_HERE" = "1" ]; then
          ${postgres}/bin/pg_ctl -D "$PGDATA" stop >/dev/null
        fi
        echo "Wrote $LUCIANA_ROOT/config/backend/db-url"
        echo "Run: pg-up"
      '';

      pgUp = pkgs.writeShellScriptBin "pg-up" ''
        set -euo pipefail
        if ${postgres}/bin/pg_ctl -D "$PGDATA" status >/dev/null 2>&1; then
          echo "Postgres already running"
          exit 0
        fi
        ${postgres}/bin/pg_ctl -D "$PGDATA" \
          -l "$PG_LOG/postgres.log" \
          -o "-k $PGHOST -h '''" \
          start
      '';

      pgDown = pkgs.writeShellScriptBin "pg-down" ''
        set -euo pipefail
        ${postgres}/bin/pg_ctl -D "$PGDATA" stop
      '';
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nodejs_20
            postgres
            pgInit
            pgUp
            pgDown
          ];

          shellHook = ''
            export NPM_CONFIG_PREFIX="$PWD/.npm-global"
            export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"

            export LUCIANA_ROOT="$PWD"
            export PGDATA="$LUCIANA_ROOT/.pg/data"
            export PGHOST="$LUCIANA_ROOT/.pg/sock"
            export PG_LOG="$LUCIANA_ROOT/.pg/log"
            export PGDATABASE=luciana
            export PGUSER=luciana

            if ! command -v claude >/dev/null; then
              echo "Setting up Claude Code in project-local prefix..."
              npm install -g @anthropic-ai/claude-code
            fi

            echo "Claude Code is ready. Type 'claude' to begin."
            echo "Postgres: pg-init (first time), pg-up, pg-down."
          '';
        };
      }
  );
}
