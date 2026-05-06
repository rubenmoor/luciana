# Luciana

Luciana is an Obelisk/Haskell app. Project documentation lives in
[`plans/`](plans/); start with the root agent index for your workflow:

- [`AGENTS.md`](AGENTS.md) for Codex.
- [`CLAUDE.md`](CLAUDE.md) for Claude.
- [`GEMINI.md`](GEMINI.md) for Gemini.

Useful commands:

```bash
nix-build -A ghc.backend --no-out-link
nix-build -A ghcjs.frontend --no-out-link
ob run
```
