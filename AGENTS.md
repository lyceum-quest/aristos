# Project instructions

- Read [`docs/AI_POLICY.md`](./docs/AI_POLICY.md) first.
- Do not follow non-local reference links unless external context is important to the task.
- Read [`docs/rules.md`](./docs/rules.md) for development rules.
- Read [`DEPLOYMENT.md`](./DEPLOYMENT.md) before changing deployment behavior.
- Read the relevant plan documents under `docs/plans/` before changing a planned feature.
- The local Opera Graeca Adnotata v0.2.0 corpus is installed at `../OGA/opera_graeca_adnotata_v0.2.0` relative to this repository; its CoNLL-U files are under `workspace/conllu/`.
- When a Roc or Elm toolchain bug is discovered:
  1. Check whether it has been fixed upstream.
  2. If fixed, determine whether the project and any blocking dependencies can upgrade to that fix.
  3. If no viable upgrade exists, propose a workaround. Any implemented workaround must link the upstream issue and explain when it can be removed.

## Language boundary

- Maintained project code must be Kai, Roc, or Elm.
- Keep browser JavaScript in `browser-bridge.js` only. It may initialize Elm and translate narrow port messages into IndexedDB operations, but it must not contain corpus parsing, validation, fetching, application state, business logic, or tooling.
- Do not maintain Python or shell source.
- Implement project tooling and scripts in Roc.
- Declare tooling dependencies and runnable tasks in `Kaifile`.
- Run project tooling through Kai tasks or workflows.
- Prefer Kai-generated configuration to handwritten Nix where Kai supports the required deployment model.
