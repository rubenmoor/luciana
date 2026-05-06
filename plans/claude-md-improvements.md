# claude-md-improvements.md

Status: reference — historical plan; most recommendations have already been
applied to `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md`.

This file remains as context for why the root instruction files use compact
plan indexes, source maps, skip-path lists, and concrete verification
commands. Do not treat the examples below as current file inventories.

The original motivation: `CLAUDE.md` listed only a few plan files and told the
agent to "read the above files" before coding. The improvements below shifted
that cost from "every session" to "only when the task touches the topic."

---

## 1. Replace the 4-file list with a complete plan index

Today (`CLAUDE.md` lines 3-6):

```
* project overview and goal: `plans/goal.md`
* structure of the project and how to run: `plans/obelisk.md`
* haskell conventions: `plans/Haskell.md`
* general best practices (forms, ids, etc.): `plans/best-practices.md`
```

Replace with a one-line-per-file index covering all of `plans/`:

```
| File | Status | Scope |
|---|---|---|
| goal.md              | spec        | What the app does, top-level features |
| architecture.md      | spec        | Layering (FE/common/BE/DB), libs, push flow |
| obelisk.md           | reference   | `ob` CLI, thunks, build commands, config dirs |
| dev-environment.md   | reference   | Local Postgres, env vars, direnv |
| Haskell.md           | reference   | Prelude (relude), default extensions, cabal stanza rules |
| ui-best-practices.md | reference   | Form labels, ids, Enter-to-submit |
| routes.md            | partial     | URL → handler map; some feature semantics incomplete |
| schema.md            | partial     | Postgres tables; some implemented |
| database-plan-1.md   | partial     | beam/postgres setup, pool, migrations |
| authentication.md    | partial     | Session cookie, bcrypt, rate-limit |
| visual-design.md     | reference   | Color tokens, layout primitives |
| daisyui.md           | reference   | DaisyUI usage notes |
| tailwind.md          | reference   | Tailwind build pipeline |
| obelisk-init-guide.md| reference   | Bootstrap notes from initial scaffold |
```

Rule under the table: **read only the files relevant to the current task.**
Drop instruction 1 ("Explore Before Coding: read the above files").

Net effect: baseline tokens loaded per session drop from ~330 lines to ~0.

---

## 2. Add a `Status:` line at the top of every plan

Convention: each `plans/*.md` opens with one of

- `Status: spec` — describes intended behaviour; no code yet.
- `Status: partial` — some of the spec is implemented; source is canonical for what's built, plan for what's pending.
- `Status: implemented` — describes existing code; if plan and source disagree, source wins.
- `Status: reference` — stable how-to / convention doc, not tied to a feature.

Why: today I have to read both plan *and* the relevant source to know which
is ground truth. The label collapses that to a single read in most cases.

This change is mechanical — one line at the top of each existing plan.

---

## 3. Inline a tiny source map into `CLAUDE.md`

```
backend/src/Backend/        Backend.hs, Api.hs, Db.hs, Auth.hs
backend/src/Backend/Auth/   Cookie.hs, Session.hs, RateLimit.hs
backend/src/Backend/Schema/ User.hs, Session.hs, PeriodEntry.hs,
                            PushSubscription.hs, NotificationPref.hs, Db.hs,
                            Migration.hs
common/src/Common/          Route.hs, Auth.hs, Api.hs, I18n.hs
frontend/src/Frontend/      Frontend.hs, Auth.hs
frontend/src/Frontend/Auth/ Widget.hs
```

Saves a `find`/`grep` round-trip whenever I need to locate a module. Update
on file moves (low frequency).

---

## 4. Add a naming-conventions block to `CLAUDE.md`

Keep `Haskell.md` as its own file — it is expected to grow. `CLAUDE.md`
continues to point at it via the index in §1.

Add a four-line cross-cutting conventions block in `CLAUDE.md` for things
that don't have a natural home in any single plan:

```
- Routes: FrontendRoute_X, BackendRoute_X, ApiRoute_X, then per-area
  AuthRoute / PeriodRoute / NotificationsRoute / PushRoute.
- Schema: one Backend.Schema.X module per table; LucianaDb in Backend.Schema.Db.
- Prelude: relude everywhere; explicit import lists except `import Relude`.
- Ids on form controls: human-readable, page-scoped (see best-practices.md).
```

---

## 5. Pin the verification commands

Today instruction 4 ("Verification Loop") just says "check that it
compiles." Replace with concrete commands so I don't re-open `obelisk.md`:

```
- Inner loop: `ob watch` (kept running in a side terminal — assume it's already up).
- Before "done": `nix-build -A ghc.backend --no-out-link` and
  `nix-build -A ghcjs.frontend --no-out-link`. The GHCJS build is the only
  way to catch frontend-only errors without `ob run`.
- End-to-end smoke: `ob run`, hit the affected route in a browser.
```

---

## 6. Add a "do not read" list

```
Skip these paths in searches and reads:
- .obelisk/impl/         — Obelisk thunk, large
- dep/                   — vendored thunks
- dist-newstyle/         — cabal build output
- static.out/            — generated assets bundle
- ghcid-output.txt       — transient compiler output
```

Prevents accidental large reads (`static.out` and `dist-newstyle` are the
worst offenders) and keeps `grep`/`find` results focused.

---

## 7. Add a routine-commands cheat sheet

A small block at the bottom of `CLAUDE.md`:

```
- Survey a Haskell package version in the pinned set (replace <pkg>):
    nix-instantiate --eval --strict -E \
      '((import ./.obelisk/impl {}).reflex-platform.ghc.<pkg>).version or "missing"'
- Build one package:    nix-build -A ghc.<pkg> --no-out-link   (or ghcjs.<pkg>)
- Dev server:           ob run
- Watch-compile:        ob watch
- REPL:                 ob repl
```

The Haskell-dep survey command is already in `CLAUDE.md`; the rest currently
live in `obelisk.md` and force a re-read.

---

## 8. Drop / soften instructions that are no longer load-bearing

- Instruction 1 ("Explore Before Coding: read the above files") — replaced
  by the index in §1 plus the per-file `Status:` in §2.
- Instruction 7 ("Subagents: use for parallel file reading...") — keep, but
  trim to one line; the current wording is longer than its content.

Keep as-is: 2 (no code without plan), 3 (one file per feature), 5 (explicit
scope), 6 (verbosity).

---

## 9. Plan-file hierarchy and the no-redundancy rule

Plan files form a tree, not a flat folder. `CLAUDE.md` is the root; feature
plans (`authentication.md`, `routes.md`, `schema.md`, …) are leaves;
overview plans (`architecture.md`, `obelisk.md`, `dev-environment.md`) sit
in between.

```
CLAUDE.md                                              [root]
├─ goal.md                                             [overview]
├─ architecture.md                                     [overview — layering, libs]
├─ obelisk.md / dev-environment.md                     [overview — build & run]
├─ Haskell.md / ui-best-practices.md / visual-design.md [reference — cross-cutting conventions]
│   └─ tailwind.md / daisyui.md                        [reference — narrower than visual-design.md]
└─ feature plans                                       [leaves]
   ├─ authentication.md
   ├─ routes.md
   ├─ schema.md
   ├─ database-spec.md / database-plan-1.md / database-plan-2.md
   └─ obelisk-init-guide.md
```

**Rule (to be added to `CLAUDE.md`'s instructions):**

> When writing or editing a plan file, avoid duplicating content that
> already lives in a file further down the tree. A file closer to the root
> should *point to* the deeper file (by relative link) rather than restate
> its content. If two files at the same level overlap, pick one as the home
> and have the other point to it.

Concrete consequences for the existing plans (apply lazily, when those
files are next touched — not as part of this change):

- `obelisk.md` ↔ `architecture.md` ↔ `dev-environment.md` overlap on
  layering and dev workflow. Pick one home per topic; the others link.
- `routes.md` currently restates auth route detail from
  `authentication.md`. The auth section in `routes.md` should shrink to a
  link plus the bare URL → constructor mapping.
- `schema.md`'s "Haskell mapping (sketch)" duplicates structure that
  `Backend.Schema.*` already carries; once those modules exist (status:
  `partial` → `implemented`), the sketch becomes a pointer to the source.

A new feature plan should assume the reader has already read `CLAUDE.md`
and the relevant overview/reference plans listed in the index. It should
not re-explain Obelisk, the prelude, the route encoder, or the schema
conventions — just link to them.

---

## Out of scope

- No changes to source code.
- No changes to existing plan content beyond adding the one-line `Status:`
  header in §2.
- `CLAUDE.md` final wording is not drafted here — this plan only specifies
  the structural changes. A second pass produces the rewritten file once
  this plan is approved.
