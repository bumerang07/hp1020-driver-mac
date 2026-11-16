# Validation — 2026-11-16, Apple Silicon

Passed:

- C filter built with `-Wall -Wextra -Werror` (SDK deprecation warnings suppressed for the supported legacy CUPS APIs).
- Swift/AppKit confirmation agent built with a macOS 13 deployment target.
- Real CUPS raster library tests with a simulated vendor converter and user confirmation: default long-edge duplex; 2/4/5 pages; odd-page blank; 1-bit and 8-bit rotation including row padding; white/black color spaces; one-page job; two copies; cancel; SIGTERM; timeout; missing agent; truncated input; invalid option; symlink response rejection; simplex passthrough.
- Agent protocol parser self-test, including invalid metadata and request filenames.
- `cupstestppd -W filters` accepted generated PPD; inherited warnings and uninstalled filter/icon remain documented in README.
- Shell syntax and app Info.plist validation.
- Actual native AppKit dialog opened in `--preview`, inspected with accessibility, screenshot saved, and Cancel closed the preview. Preview has no printing side effects.
- macOS `cgpdftoraster` rendered the supplied CUPS A4 PDF to a 31,569,066-byte raster using the generated PPD.

Not passed / not verified:

- A direct invocation of the installed HP converter outside the CUPS backend did not finish within 45 seconds. An earlier tiny synthetic header was rejected because it omitted HP's private raster settings. Neither invocation contacted USB or printed. These are not evidence that the hardware conversion chain works or fails under CUPS; it needs a real backend test.
- No installation into the user's system print queue was performed.
- No physical HP 1020 print, actual scheduler/backend sandbox test, system print-dialog option test, Intel build/run, or notarization was performed.

Next integration check: install into an idle, already working HP 1020 queue, reopen the print dialog, verify long-edge duplex is default, print four numbered pages, confirm the paper prompt, inspect page pairs and orientation, then test five pages and cancellation. Keep the original PPD backup until this is confirmed.

## IPC permission correction after first hardware attempt

CUPS connected to USB but the wrapper exited before raster processing with `Confirmation agent is not installed for this user`. The agent itself was running. Corrected directory open mode to O_SEARCH and metadata file modes from 0600 to 0644. Added a regression assertion for heartbeat/reply file modes and a `--check-agent USER` diagnostic. The privileged update script tests this from `_lp`, preserves held jobs and does not resume printing. Local raster and agent tests pass; deployment of this correction still requires administrator authentication.
