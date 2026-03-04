---
description: Git workflow and commit conventions
alwaysApply: true
---
# Git Conventions

## Commit Messages
- Use imperative mood: "Fix JB2 init sequence", not "Fixed" or "Fixes"
- First line: concise summary under 72 characters
- Body (optional): explain *why*, not *what* — the diff shows the what
- Reference DjVu.js when a fix aligns our code with the reference implementation

## Branching
- `main` is the primary branch
- Feature work can use short-lived topic branches

## What to Commit
- Source code changes (`Sources/`, `Package.swift`, `scripts/`)
- Documentation (`CLAUDE.md`, `docs/`)
- Test files only if small (< 1 MB)

## What NOT to Commit
- `.build/` directory (already in `.gitignore`)
- Generated `.app` bundles
- Large binary test files
- Temporary debug output (`/tmp/djvu_*.png`)
