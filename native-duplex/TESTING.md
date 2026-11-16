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

## Cancellation watchdog and prompt visibility

Added an isolated process group for the HP converter, nonblocking wait, SIGTERM on cancellation, forced group termination after 2 seconds, and a 30-minute per-pass timeout. Raster tests include a deliberately hung converter that ignores SIGTERM, checking both cancellation and timeout. Prompt windows use modal-panel level, remain visible after deactivation, join Spaces and request user attention. These changes alone did not fix the converter stall; the subsequent investigation below identified the regular-file stdin incompatibility.

## Resolved converter stall: restore pipe semantics

The wrapper had supplied a seekable temporary file as converter stdin. Reproduced a hang with the real installed HP converter and a synthetic CUPS A4 raster when stdin was a regular file, even when stdout was a pipe. With pipe stdin and pipe stdout the same converter completed successfully. The wrapper now feeds the private spool through a nonblocking pipe while monitoring cancellation and its watchdog. This preserves the input semantics of the original CUPS filter chain.

Verified on this Mac without a USB backend or physical printing:

- Actual wrapper + installed HP converter, one synthetic page: exit 0, 265181 bytes, approximately 0.51 seconds.
- Actual wrapper + installed HP converter, two synthetic pages with simulated reload confirmation: exit 0, 530378 bytes; exactly one request, both passes complete and request/reply cleaned up.
- Raster fixture now rejects regular-file stdin in the converter invocation, preventing regression.
- Existing raster ordering, blank padding, rotation, cancellation, hung-child watchdog, timeout and agent protocol tests pass.

A full physical duplex test after installing this correction is still required. The failed physical job 631 was cancelled; no replacement job was submitted by these tests.

Cancellation follow-up: an orphaned HP converter from job 631 remained after the scheduler cancelled its parent. Added direct-PID signalling in addition to process-group signalling, and updater recovery limited to orphaned HP converter processes belonging to the installing user's jobs. No other queue or active job is stopped by the updater.

## Physical refeed orientation correction

The user confirmed successful two-pass printing, but the back side was upside down with the normal stack transfer. Corrected the HP1020 bottom-edge-first mapping: LongEdge (default) rotates backs 180 degrees; ShortEdge leaves backs unrotated. Tests now assert both binding modes for 1-bit and 8-bit raster, plus the implicit default. Page pairing and ordering are unchanged. Physical confirmation of the corrected orientation is pending.
