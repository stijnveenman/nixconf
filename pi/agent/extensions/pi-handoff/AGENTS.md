# pi-handoff extension

This is a repository-managed global Pi extension. Home Manager links `pi/agent/extensions/` into `~/.pi/agent/extensions/`, where Pi discovers this extension for every project; do not add this entrypoint to the repository root `package.json` or `pi/agent/settings.json`.

## Dependency boundary

- `@narumitw/pi-tui-kit` is the runtime dependency and is pinned in `package.json`.
- `@earendil-works/pi-coding-agent` and `@earendil-works/pi-tui` are Pi-provided peer packages; they are development dependencies here for TypeScript resolution and must not be bundled as runtime dependencies.
- Keep `node_modules/` untracked; refresh dependencies with `npm install` from this directory.

## Pi TUI Kit API

The package is a reusable UI library, not an extension. Prefer its public APIs over custom components, in this order: Pi `ctx.ui` and `@earendil-works/pi-tui`, then `@narumitw/pi-tui-kit`, and only then an extension-owned component.

- `defineMenu()` creates typed menus; `runMenu()` adapts them to TUI and RPC, owns navigation, cancellation, screen state, and unsupported-mode results.
- Standard screens are `actions`, `detail`, `browse`, `choice`, `settings`, `input`, `review`, and `multiSelect`.
- Standalone flows include `runTask`, `runConfirmation`, `runDocumentReview`, `runMultiSelect`, `runLiveChoice`, `runQuestionnaire`, and `runSecretInput`.
- Use `runCustomInteraction` only when the standard screens and standalone flows cannot express the interaction.
- Use `sanitizeTerminalText` or `sanitizeTerminalDocument` before displaying untrusted model text, paths, IDs, or documents. Keep raw payloads separate from display text.
- Use `HorizontalRule`, `EditorStatusWidget`, and `renderBoundedFrame` for passive, width-safe presentation; rebuild width-sensitive output on resize.
- Use `formatInteractionHints` with callback-provided keybindings. Do not advertise shortcuts that cannot receive input or are consumed by an earlier listener.
- `@narumitw/pi-tui-kit/markdown` provides lazy Mermaid Markdown preparation and synchronous finalized-message transformation. Revalidate ownership after every await.
- `@narumitw/pi-tui-kit/testing` provides `createTuiHarness` and `createRpcHarness`; import it only from tests.

The consuming extension owns domain state, persistence, settings schemas, confirmations, session generation, shutdown policy, preview rollback, credential storage, and product-specific copy. Kit owns UI lifecycle, cancellation, stale checks, disposal, navigation, formatting, and TUI/RPC adaptation.

For asynchronous UI, pass an owner `AbortSignal`, honor it in all work, provide `isCurrent()` when state can become stale, and revalidate session/generation/context after every `await`. Do not retain an `ExtensionContext` after session replacement, reload, or shutdown. Keep `Ctrl+C` as a hard-cancel path and distinguish Back from Close where the API exposes both.

## API references

Read the upstream documentation before changing the interaction contract:

- README: https://github.com/narumiruna/pi-extensions/blob/main/packages/pi-tui-kit/README.md
- Full API guide: https://github.com/narumiruna/pi-extensions/blob/main/packages/pi-tui-kit/docs/api.md
- Package manifest and peer/runtime dependency declarations: https://github.com/narumiruna/pi-extensions/blob/main/packages/pi-tui-kit/package.json
- Source and tests: https://github.com/narumiruna/pi-extensions/tree/main/packages/pi-tui-kit/src and https://github.com/narumiruna/pi-extensions/tree/main/packages/pi-tui-kit/test

The API guide documents the current public API version, screen contracts, mode behavior, ownership boundary, sanitization, lifecycle rules, and testing harnesses. Treat the upstream guide as authoritative if this summary becomes stale.
