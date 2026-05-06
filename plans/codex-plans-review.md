# codex-plans-review.md

Status: reference — resolved review log

This file records a documentation review that has been addressed. Keep it as a
change log, not as an active task list.

## Resolved Findings

1. **Database plan names are canonical.**
   - `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` now list
     `database-spec.md`, `database-plan-1.md`, and `database-plan-2.md`.
   - `database-plan-1.md` is titled with its actual filename.

2. **Root plan indexes are aligned.**
   - All three root instruction files list the database split and
     `obelisk-init-guide.md`.

3. **Status labels were reconciled.**
   - `authentication.md` stays `partial` and now says the source is canonical
     for exact rate-limit and timezone-refresh behavior.
   - `routes.md` now says routes and handler wiring exist, while some feature
     semantics remain incomplete.

4. **Backend monad docs match implementation.**
   - `backend-spec.md` now documents `type App = ReaderT Env Snap`.

5. **Superseded backend plan is marked historical.**
   - `backend-plan-1.md` is a `reference` plan superseded by
     `backend-plan-2.md`.

6. **Frontend API guidance is consistent.**
   - `backend-plan-2.md` keeps `Frontend.Api.apiUrl` and the Obelisk route
     GADTs as the canonical URL-rendering path, while documenting derived
     Servant clients as available.

7. **Tailwind/daisyUI build docs are consistent.**
   - `daisyui.md` now points to the standalone Tailwind CLI build in
     `tailwind.md` and removes stale `package.json` guidance.

8. **Broken relative links were fixed.**
   - `visual-design.md` now links correctly to `daisyui.md`, `goal.md`, and
     `../static/default.nix`.

9. **Stale frontend helper path was fixed.**
   - `ui-best-practices.md` now points at
     `frontend/src/Frontend/Widget/Form.hs`.

10. **Toast flood-guard docs match implementation.**
    - `toasts.md` now documents the implemented cap of 5 visible toasts.

11. **Registration debugging plan is marked resolved.**
    - `debugging-plans/registration-sql-error.md` is historical context, not
      a pending debugging task.

12. **`claude-md-improvements.md` is historical.**
    - It is marked `reference` and no longer presents stale inventories as
      current tasks.

13. **README has an entry point.**
    - `README.md` now points humans at the root instruction files and common
      build commands.
