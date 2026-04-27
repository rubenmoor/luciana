# CLAUDE.md

* project overview and goal: `plans/goal.md`
* structure of the project and how to run: `plans/obelisk.md`
* haskell conventions: `plans/Haskell.md`

# instructions

1. **Explore Before Coding:** read the above files
2. **No code without plan:** the current state of the code must always be reflected in some markdown file in the `plans/` directory; my prompts usually are meant to edit a plan file, until I ask you to *implement a plan*; whenever you write to `plans/`, stop and let me review before proceeding with implementation
3. **Structure of `plans/`:** every feature gets a new markdown file in `plans/`
4. **Verification Loop:** after changes to the code, check that it compiles and try to fix any error
5. **Explicit scope:** the markdwon file in `plans/` specifies files and functions; whenever changes outside the specified scope are necessary, first make changes to the plan and nothing else
6. **Verbosity:** don't explain stuff to me unless I ask you
7. **Subagents:** Use subagents for parallel file reading or research, but do not spawn them for simple single-file refactors.

