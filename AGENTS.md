# Project Instructions

## Language boundary

- Maintained project code must be Kai, Roc, or Elm.
- Keep browser JavaScript in `browser-bridge.js` only. It may initialize Elm and translate narrow port messages into IndexedDB operations, but it must not contain corpus parsing, validation, fetching, application state, business logic, or tooling.
- Do not maintain Python or shell source.
- Implement project tooling and scripts in Roc.
- Declare tooling dependencies and runnable tasks in `Kaifile`.
- Run project tooling through Kai tasks or workflows.
- Prefer Kai-generated configuration to handwritten Nix where Kai supports the required deployment model.
