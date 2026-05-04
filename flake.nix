{
  description = "Dev environment for Claude Code and Gemini CLI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        postgres = pkgs.postgresql_16;
        
        # Native dependencies for Gemini/Claude credential storage
        nativeDeps = with pkgs; [
          libsecret
          pkg-config
          glib
        ];

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
          echo "postgresql://$PGUSER@/$PGDATABASE?host=$PGHOST" \
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
            google-cloud-sdk # Essential for 'gcloud auth' and Gemini integration
            postgres
            pgInit
            pgUp
            pgDown
          ] ++ nativeDeps;

          shellHook = ''
            export NPM_CONFIG_PREFIX="$PWD/.npm-global"
            export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"
            
            # Ensure native libraries are visible for credential helpers
            export LD_LIBRARY_PATH="${pkgs.libsecret}/lib:${pkgs.glib.out}/lib:$LD_LIBRARY_PATH"

            export LUCIANA_ROOT="$PWD"
            export PGDATA="$LUCIANA_ROOT/.pg/data"
            export PGHOST="$LUCIANA_ROOT/.pg/sock"
            export PG_LOG="$LUCIANA_ROOT/.pg/log"
            export PGDATABASE=luciana
            export PGUSER=luciana

            # Install Gemini CLI if missing
            if ! command -v gemini >/dev/null; then
              echo "Installing Gemini Code Assist CLI..."
              npm install -g @google/gemini-cli
            fi

            # Install Claude Code if missing
            if ! command -v claude >/dev/null; then
              echo "Setting up Claude Code..."
              npm install -g @anthropic-ai/claude-code
            fi

            echo "-------------------------------------------------------"
            echo "Environment Ready for Luciana Development"
            echo "-------------------------------------------------------"
            echo "Gemini: Run 'gemini login' to authenticate via gcloud."
            echo "Claude: Run 'claude' to begin."
            echo "Postgres: pg-init, pg-up, pg-down."
            echo "-------------------------------------------------------"
          '';
        };
      }
    );
}
