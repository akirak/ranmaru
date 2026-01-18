# Repository Guidelines

## Project Structure & Module Organization
- `lib/` holds the core library modules (e.g., `ranmaru.ml`, `lsp_utils.ml`, `import.ml`).
- `ranmaru/` contains the CLI entry point (`main.ml`) that wires up the library.
- `test/` contains the Alcotest suite (`test_main.ml`), with its dune stanza in `test/dune`.
- `assets/` stores documentation images used by the README.
- Build metadata lives in `dune-project`, `ranmaru.opam`, and `flake.nix`.

## Build, Test, and Development Commands
- `nix develop`: enter the recommended dev shell.
- `dune build`: build the library and executable.
- `dune exec ranmaru -- --client /tmp/client.sock --master /tmp/master.sock`: run locally.
- `opam install --deps-only .`: install deps when not using Nix.
- `dune runtest` or `dune build @runtest`: run the test suite.
- `nix build`: build the Nix package; binary at `./result/bin/ranmaru`.
- `nix fmt`: format OCaml and other files (uses `ocamlformat`).

## Coding Style & Naming Conventions
- Formatting is enforced by `ocamlformat` with settings in `.ocamlformat` (margin 77, LF). Run `nix fmt` before submitting.
- Use `snake_case` for values/functions and `CamelCase` for modules; module filenames follow the module name (`foo_bar.ml` -> `Foo_bar`).
- Keep public interfaces in `*.mli` and match implementation names exactly.

## Testing Guidelines
- Tests use Alcotest; add new cases as `test_case` entries in `test/test_main.ml` or new `test_*.ml` files referenced from `test/dune`.
- Favor fast, deterministic tests; no coverage target is enforced, but new features should include tests.

## Commit & Pull Request Guidelines
- Recent history uses Conventional Commit-style prefixes (e.g., `ci:`, `style:`, `docs(readme):`, `chore(nix):`). Follow the same pattern with a short, imperative summary.
- PRs should include a clear description, how to test, and any relevant issues. Run `dune build`, `dune runtest`, and `nix fmt` before opening.

## Configuration Tips
- The CLI accepts `--client` and `--master` socket paths; environment variables `RANMARU_CLIENT_SOCKET` and `RANMARU_MASTER_SOCKET` are supported for local testing.
