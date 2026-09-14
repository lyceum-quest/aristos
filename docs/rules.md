# Development rules

## Workflow

- After every code or configuration change, run `kai workflow release`. It must pass on every commit.
- Run project tooling through Kai tasks or workflows. Declare new tooling dependencies and runnable tasks in `Kaifile`.
- Do not commit unless explicitly instructed. Never push, create an issue, or open a pull request.
- If asked why a problem occurs, explain it so the developer can fix it. Do not edit files unless asked.
- Use a subagent for self-contained work when one is available, preserving the main context for design discussions.
- When comments are added to a file for you to address, answer the questions without removing or rewriting those comments unless asked.

## Implementation

- Favor the smallest change that implements the requested behavior and respects the project boundaries in [`AGENTS.md`](../AGENTS.md).
- Keep application state, corpus parsing, validation, fetching, and business logic in Elm. Keep project tooling in Roc. Restrict `browser-bridge.js` to Elm initialization and narrow IndexedDB port translation.
- Keep pure data transformations separate from side effects.
- Do not edit generated output in `.kai/`, `elm.js`, `dist/`, or `preload/`; regenerate it through the corresponding Kai task or workflow.
- Use Roc's `\\` syntax for static multiline strings. Use `Str.join_with` only when interpolation or composition is required.
- Do not add tests unless explicitly asked to add a specific set or complete an already-started set.
- Do not create or modify documentation unless explicitly requested.

## Version control

- Use conventional commit subjects in the form `type: description`.
- Do not add a fix commit for defects introduced on the same feature branch; amend or reorganize the feature work instead.
- Keep commits independently useful and safe to merge. Prefer roughly +50/-50 lines per commit and avoid exceeding +500/-500 where possible.
- Preserve merge commits when rebasing or reorganizing history.

## Issues and pull requests

- Never create an issue or pull request on behalf of the user.
- If asked to prepare one, provide text for human review instead of submitting it.
