# biome / pnpm exec exit-254 reproduction

Minimal reproduction for [biomejs/biome#12344](https://github.com/biomejs/biome/issues/12344): biome CLI intermittently exits **254** with

```
[warn] Linter process terminated abnormally (possibly out of memory)
```

when spawned through **pnpm** — including for `biome --version`, which does no linting.

## Environment where it reproduces

| Component | Version |
|---|---|
| @biomejs/biome | 2.5.14 (native `@biomejs/cli-linux-x64`) |
| pnpm | 10.15.0 |
| node | v24.21.0 |
| OS | Linux x86_64 (7-core, 7.8 GiB RAM) |

## Run it

```bash
pnpm install
./repro.sh          # or: pnpm repro
```

Each iteration invokes the same binary two ways and prints pass/fail counts:

- `./node_modules/.bin/biome --version` (direct)
- `pnpm exec biome --version` (pnpm-spawned)

**On an affected machine during a failing window**, expect output like:

```
direct ./node_modules/.bin/biome : 30 pass / 0 fail
pnpm exec biome                  : 0 pass / 30 fail
REPRODUCED: pnpm-spawned biome failing while the identical direct invocation passes
```

Observed live on the affected machine (window state flipped mid-session):

| Invocation | Failing window | Healthy window |
|---|---|---|
| `pnpm exec biome --version` | 254, 10/10 | 0, 30/30 |
| `pnpm exec biome check .` | 254, 5/5 | 0 |
| `./node_modules/.bin/biome check .` | 0, 5/5 | 0 |
| native binary direct (`.../cli-linux-x64/biome`) | 0 | 0 |
| `pnpm exec <path-to-native-binary> --version` | 0 | 0 |
| `strace -f pnpm exec biome check .` | **0** (untraced retry seconds later → 254) | 0 |
| `BIOME_THREADS=1 pnpm exec biome ...` | 254 | 0 |

## Why this may not reproduce on GitHub CI

The failure is **intermittent and machine-dependent**: it appears in multi-minute windows on long-running, multi-user dev machines and has never been observed on isolated CI runners (fresh VM, single user, single biome invocation, different spawn context). A clean CI run passing does not contradict the report — the same commit linted green in CI while failing locally minutes apart.

If `./repro.sh` passes on your machine, re-run it periodically over a longer period on a machine matching the environment above.

## What the evidence points at

- Not OOM: 4+ GiB free during failures; `--version` spawns no lint workers.
- Not the daemon: `--use-server` is opt-in; `~/.cache/biome` empty; no biome processes during failures.
- pnpm-specific spawn path: `pnpm exec biome` → sh shim → JS wrapper (`@biomejs/biome/bin/biome`) → `spawnSync` native binary. `pnpm exec <native-binary>` passes while `pnpm exec biome` fails in the same window.
- Not env alone: replaying pnpm's full child env (`pnpm exec env` capture) and spawning the wrapper via `node child_process.spawnSync` passes.
- Timing-sensitive: `strace -f` around the pnpm invocation makes the failure disappear — consistent with a startup race in the native binary's worker/runtime init, which exit 254 wraps as "terminated abnormally (possibly out of memory)".
