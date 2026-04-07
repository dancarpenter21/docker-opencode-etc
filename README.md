## Docker Opencode Etc

A development container with Opencode, shells and editors, Miniconda (Python 3.10 / 3.12 / 3.13 + NumPy/Pandas), Rust (stable via rustup), Node.js LTS (`node`, `npm`, `npx`), and **prefetched** Rust/npm dependency trees under `~/prefetch` so Cargo and npm caches are hot for offline-style workflows.

### Build

```bash
docker build -t docker-opencode-etc:local .
```

### Run (interactive zsh)

```bash
docker run -it --rm -v "$PWD:/workspace" docker-opencode-etc:local
```

Default command is a **login zsh** (`opencode` is on `PATH`; start `opencode` or `tmux` when you want).

### Prefetch / offline use

The image includes:

- **`/home/opencode/prefetch/rust`** — `Cargo.toml` + `Cargo.lock`; `cargo fetch --locked` has been run so `~/.cargo` is populated for that graph.
- **`/home/opencode/prefetch/node`** — `package.json` + `package-lock.json` + `scripts/`; `npm ci` has been run so `~/.npm` and a reference `node_modules` exist for that lockfile.

During the image build, the Dockerfile also runs **`CARGO_NET_OFFLINE=true cargo fetch --locked`** and **`npm ci --offline`** (after removing `node_modules`) to confirm those caches are sufficient for a clean offline reinstall **for the same lockfiles**.

**Limits:**

- Work you mount at `/workspace` with **different** `Cargo.lock` / `package-lock.json` may still need crates or tarballs that are **not** in the image — that would require network **or** rebuilding this image with updated `prefetch/` lockfiles while online.
- Adding new Python packages needs an image rebuild or network access to PyPI/conda (not verified offline in the same way).

### Air-gapped transfer

Build the image on a machine with network access, then move the artifact to the isolated environment, for example:

```bash
docker save docker-opencode-etc:local | gzip > docker-opencode-etc.tar.gz
# On the isolated host:
gunzip -c docker-opencode-etc.tar.gz | docker load
```

Use an internal registry instead if your policy prefers it.

### Updating prefetch lockfiles

Replace the files under [`prefetch/rust/`](prefetch/rust/) and [`prefetch/node/`](prefetch/node/) (at minimum `Cargo.lock` and `package-lock.json`, plus matching `Cargo.toml` / `package.json` and any scripts required by `npm` lifecycle hooks), then rebuild the image.
