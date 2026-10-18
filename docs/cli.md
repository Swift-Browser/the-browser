# The `medusa` command

`medusa` drives a running Medusa from the terminal with Python and [pydoll](https://pydoll.tech) 3.0. It's a separate
download, not part of the app bundle. The app ships `install.sh`, and runs it when the user opts in during onboarding
or in Settings ("Let the medusa command control Medusa").

Code: `apps/cli` (`medusa_cli`, `install.sh`, `scripts/build.sh`). Dependencies are pinned with hashes in
`apps/cli/requirements.lock` (regenerate with `uv pip compile requirements.in --python-version 3.13
--python-platform aarch64-apple-darwin --generate-hashes --no-annotate --no-header -o requirements.lock`, then copy
the pins into `pyproject.toml`).

## Commands

- `medusa exec [CODE | -] [-f FILE] [--data-dir DIR] [--port N] [--ws URL] [--timeout S] [--json]` runs Python with
  top-level `await`. In scope: `browser` (pydoll `Chrome`), `tab` (the page shown in Medusa's last focused window,
  from `GET /medusa/active?token=…` on the token path, so it holds while the window is covered; `--port`/`--ws` test
  servers fall back to visible and focused, else visible; with no page, as on New Tab, it's a placeholder that raises
  `NoPageTab` on first use), `tabs` (http, https, about, data and blob pages, plus what `new_tab` opens, minus
  the New Tab's prewarmed `about:blank`: on the token path every `about:blank` that isn't the active page, on test
  servers the hidden ones),
  `new_tab(url, background=True)`, `js(expression, tab=None)` (default: `tab`, else the last `new_tab`), `By`, `Key`,
  `asyncio`, pydoll's exports and its common exceptions. It prints the last expression's value. Exit 0 done, 1 the
  code raised or timed out (default 300 s), 2 Medusa can't be reached or closed the browser socket (it watches the
  socket, so turning the setting off ends an idle run at once), 130 interrupted.
- `medusa skills install --target general|codex|claude-code|cursor|opencode [--target …] [--project]` installs the
  agent skill (`medusa_cli/skill`: `SKILL.md` and `references/pydoll.md`) into `~/.agents/skills` (general, codex),
  `~/.claude/skills`, `~/.cursor/skills` or `~/.config/opencode/skills`; with `--project`, into `./.agents/skills`,
  `./.claude/skills`, `./.cursor/skills` or `./.opencode/skills`. It replaces only its own `medusa` folder.
- `medusa --version`, `medusa --help`, `medusa exec --help`.

`exec` never quits Medusa: it refuses `browser.stop()`, and every WebSocket it opens checks each outgoing message (and
refuses fragmented sends), so
`Browser.close`, `Browser.crash` and `Browser.crashGpuProcess` never leave the process, whether sent one at a time, in
an `execute_commands` batch (checked whole before anything is sent) or straight on the socket. On exit (normal, an
exception or Ctrl-C) it closes only its own page and browser WebSockets. Its WebSockets always connect directly,
ignoring `http_proxy`, `ws_proxy` and the like, so no proxy sees the token.

## How it finds Medusa

1. `--ws URL`, a browser WebSocket URL.
2. `--port N`, a plain DevTools server on 127.0.0.1 (`/json/version`). For test servers only.
3. `$MEDUSA_CDP_URL`, like `--ws`.
4. `<data dir>/Chromium/MedusaControl.json`, with `--data-dir` or `$MEDUSA_DATA_DIR`, else the installed app's
   `~/Library/Application Support/com.medusa.browser/Chromium/MedusaControl.json`.

The active-page route is `GET http://127.0.0.1:P/medusa/active?token=<token>`: `{"targetId": "<id>"}`, or `null` when
New Tab or an Medusa view is showing; anything else is a 404. The CLI calls it directly (no proxy, no Origin header)
with the token redacted like everywhere else, and falls back to the visibility check if it fails.

The app writes `MedusaControl.json` when the setting is on:
`{"port":P,"browser":"/devtools/browser/<guid>","token":"…","pid":…,"generation":N}`. The CLI opens it without
following links and trusts it only when it's a regular file the user owns, mode 0600, and `pid` is alive. It connects
to `ws://127.0.0.1:P<browser>?token=<token>`; pydoll keeps the query on every `/devtools/page/<id>` URL, so page
sockets carry the token too. A missing, stale or unsafe file, or a refused connection, prints one line and exits 2:
`Medusa isn't running, or "Let the medusa command control Medusa" is off in Settings.` There's no port scanning and no
`/json` fallback on this path. The token never reaches the output: stdout and stderr are redacted as a stream (a token
split across writes is held back until it's complete), and so are log records and everything a logging handler
formats, tracebacks included. pydoll's loggers stay at ERROR. The stream holds back only a tail that could start a
registered token and releases everything on `flush()`, at exit and on SIGTERM or SIGHUP (exit 143). A token printed in
two parts with an explicit flush between them gets through; that gap is accepted.

## Install and upgrade

`install.sh [--version V] [--sha256 DIGEST] [--uninstall]` (run with `/bin/sh`; `--help`):

- Downloads `https://github.com/mantrakp04/medusa/releases/download/v<V>/medusa-cli-<V>-macos-arm64.tar.gz` (https only)
  into a private temp dir. Without `--version` it takes the latest release that has the asset. `--sha256` is the only
  digest it trusts (the app passes `Medusa.app/Contents/Resources/medusa-cli.sha256`, which the signed bundle pins), and
  a download needs it: a `.sha256` from the same release would only prove the tarball came from wherever the tarball
  came from. Only a `file://` `MEDUSA_CLI_URL` (tests) may go without it, reading `<url>.sha256`. A Debug build has no
  pinned digest, so it installs only that way.
- Verifies the digest, refuses entries outside `medusa-cli-<V>/`, `..` paths, hard links and links pointing outside the
  tree, plus names with control characters, backslashes or ` -> `, extracts to `$MEDUSA_CLI_HOME/<V>.partial`, checks
  the extracted tree again (`find`, no line parsing), renames it to `<V>`, and swaps `current` atomically.
- It keeps the current and the previous version, and any version a running `medusa` uses: `medusa_cli` writes
  `<V>/.leases/<pid>` when it starts (from the launcher or `python -m medusa_cli`) and removes it at exit. A lease
  counts only while a process with that pid runs and started no later than the lease was written (`ps -o lstart`
  against the lease's mtime), so a reused pid doesn't pin a version.
- Links `$MEDUSA_CLI_BIN_DIR/medusa` (default `~/.local/bin`) to `current/bin/medusa`. It replaces only a link that
  already points into `$MEDUSA_CLI_HOME` and refuses anything else. With the default bin dir off the login shell's
  PATH, it adds `export PATH="$HOME/.local/bin:$PATH"` to `~/.zprofile` once.
- A version that is already current is a no-op. Two runs never overlap: each takes a flock on
  `$MEDUSA_CLI_HOME/.lock` through fd 9 (`/usr/bin/lockf -s -t 120 9`). The kernel drops it when the run exits, even on
  SIGKILL; a run that waits 120 s prints `error another install is still running`. Uninstall leaves the empty `.lock`
  file, since deleting a lock file other runs may have open would split the lock.
- Output for the app, one line each: `step resolve|download|verify|install|link`, `version <v>`, `path <rc file>`,
  then `installed <bin path>` or `uninstalled`, or `error <message>` with exit 1.

`$MEDUSA_CLI_HOME` defaults to `~/Library/Application Support/Medusa/CLI`. The installed version is
`basename "$(readlink "$MEDUSA_CLI_HOME/current")"`; the app reads that link to decide whether to upgrade, and after an
app update it runs `install.sh --version <app version> --sha256 <pinned digest>` in the background. The CLI never
updates itself.

## Build and release

`apps/cli/scripts/build.sh <version> <out dir>` writes `medusa-cli-<version>-macos-arm64.tar.gz` and its `.sha256`:
python-build-standalone CPython 3.13 (release and sha256 pinned in the script), the locked dependencies and
`medusa_cli` in its site-packages, pruned of tests, idlelib, Tk, ensurepip, the unused libpython dylib and
`__pycache__`, plus `bin/medusa`, an sh launcher that resolves its links and runs `python3 -I -m medusa_cli`. About
14 MB; 41 MB installed. `medusa --version` takes about 10 ms; the first `exec` about 1 s while Python writes its
bytecode cache, later ones about 0.15 s.

`scripts/release.sh` builds it into the release's dist dir after the export and writes its digest to
`Medusa.app/Contents/Resources/medusa-cli.sha256` before the app is signed. `publish-nightly.sh` and the stable
`gh release create` in the release skill upload the tarball and its `.sha256`.

## Test

Never against the real home. A hidden instance's plain DevTools port works with `--port`:

```sh
scripts/agent/ac launch <Medusa.app> --data /tmp/medusa-cli-test --onboarded
medusa exec --port <port> 't = await new_tab("https://example.com"); await t.title()'
scripts/agent/ac quit /tmp/medusa-cli-test
```

The `MedusaControl.json` path needs the app's token server: Chrome's plain server accepts `?token=` on the browser
socket but answers 500 on page sockets with a query. For the installer:

```sh
apps/cli/scripts/build.sh 0.0.1 /tmp/medusa-cli-out
HOME=/tmp/medusa-cli-home MEDUSA_CLI_URL=file:///tmp/medusa-cli-out/medusa-cli-0.0.1-macos-arm64.tar.gz \
  /bin/sh apps/cli/install.sh
HOME=/tmp/medusa-cli-home medusa skills install --target claude-code
```
