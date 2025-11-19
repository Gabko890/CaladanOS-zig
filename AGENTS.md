# Repository Guidelines

## Project Structure & Module Organization
- `src/kernel/` — kernel entry and core subsystems (e.g., `main.zig`, `idt.zig`, `mm/`).
- `src/arch/x86_64/` — architecture specifics: `boot/` (Multiboot2, `boot.S`), `cpu/` (CPUID, IDT stubs), `linker/` (`kernel.ld`, `ld_exports.zig`).
- `src/drivers/` — device code: `video/console.zig`, `debug/serial.zig`.
- `include/` — public headers; `boot/` — GRUB config; `tools/` — scripts; `build/` — local config; `docs/` — design notes.
- Build outputs: `.zig-cache/`, `zig-out/` (do not edit).

## Build, Test, and Development Commands
- `zig build kernel` — builds `zig-out/bin/kernel.elf`.
- `zig build iso` — builds UEFI GRUB ISO at `zig-out/bin/kernel.iso`.
  Requires `grub-mkimage`, `xorriso`, and `mtools` or `mkfs.vfat`.
- `zig build config` — interactive options (architecture, serial); writes `build/config.json`. Needs `dialog`.
- `./start_qemu.sh` — boots the ISO with OVMF in QEMU (needs `qemu-system-x86_64` and `OVMF_CODE.fd`).

## Coding Style & Naming Conventions
- Run `zig fmt` before committing. Use 4‑space indentation, no tabs.
- Filenames: `snake_case.zig` (e.g., `console_init.zig`).
- Types: UpperCamel (`BootInfo`); functions/vars: lowerCamel (`init`, `initializeFrom...`).
- Keep arch‑specific code under `src/arch/x86_64/`; avoid host OS APIs (freestanding target).

## Testing Guidelines
- Prefer Zig `test` blocks colocated with code (or `*_test.zig` beside it) for library‑style components (e.g., under `src/lib/`).
- For kernel subsystems, add lightweight self‑tests runnable under QEMU that print PASS/FAIL to console/serial.
- Example: run the ISO, capture serial via `-serial stdio` (already set in `start_qemu.sh`).

## Commit & Pull Request Guidelines
- Commits: concise, imperative summaries; prefix subsystem when helpful (`mm:`, `idt:`, `console:`). Example: `mm: add frame allocator selftests`.
- PRs: include a clear description, linked issues, how you tested (commands, logs/screenshots of boot output), and any `build.zig` changes (new modules/imports).
- Keep diffs focused; document new files and their directory placement rationale.

## Configuration Tips
- Treat `build/config.json` as local developer config; don’t commit unless intentionally updating defaults.
- If enabling serial output, use `zig build config` and verify logs appear on QEMU stdio.
