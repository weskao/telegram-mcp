# sync-upstream

Sync this fork with upstream (chigwell/telegram-mcp).

## Two scenarios

### A. Routine: update README.upstream.md only

No merge, no conflict. Just keep the upstream README reference fresh.

```bash
make sync-upstream-readme
```

Then commit:

```bash
git add README.upstream.md
git commit -m "docs: sync README.upstream.md from upstream"
```

---

### B. Full upstream merge (pull in bug fixes / new tools)

1. Fetch and merge upstream:

   ```bash
   git fetch upstream
   git merge upstream/main
   ```

2. If `README.md` shows a conflict, keep the fork version and update the upstream copy:

   ```bash
   git checkout --ours README.md
   git add README.md
   make sync-upstream-readme
   git add README.upstream.md
   ```

3. Resolve any other conflicts normally, then commit.

---

## Rules

- **Never edit `README.upstream.md` by hand** — always regenerate via `make sync-upstream-readme`.
- `README.md` is the fork landing page; `README.upstream.md` is byte-identical to upstream.
- After merging, run `uv run pytest` and the formatting checks (`uv run black --check .`, `uv run flake8 .`) to confirm nothing broke.
