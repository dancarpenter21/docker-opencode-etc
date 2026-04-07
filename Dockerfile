# docker-opencode-etc: Opencode CLI + zsh/tmux/neovim + Miniconda + Rust (stable) + Node LTS (npx).
#
# ghcr.io/anomalyco/opencode is Alpine/musl; this image uses Ubuntu + glibc for Conda and native tooling.
# Opencode CLI: glibc release from GitHub (OPENCODE_VERSION).
# Offline-oriented: prefetch/rust and prefetch/node ship Cargo.lock + package-lock.json for cache warming and build-time verification.
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG OPENCODE_VERSION=1.3.17

ENV BUN_RUNTIME_TRANSPILER_CACHE_PATH=0 \
    SHELL=/usr/bin/zsh \
    PATH=/opt/miniconda3/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    libssl-dev \
    pkg-config \
    ripgrep \
    tmux \
    zsh \
    neovim \
    && rm -rf /var/lib/apt/lists/*

# Node.js Active LTS (22.x) — provides node, npm, npx.
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && node --version && npm --version && command -v npx

# glibc opencode CLI
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
        amd64) t=x64 ;; \
        arm64) t=arm64 ;; \
        *) echo "unsupported dpkg arch: $arch" >&2; exit 1 ;; \
    esac; \
    mkdir -p /tmp/oc; \
    curl -fsSL "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-${t}.tar.gz" \
        | tar -xz -C /tmp/oc; \
    oc="$(find /tmp/oc -type f \( -name opencode -o -path '*/bin/opencode' \) -perm -111 | head -1)"; \
    test -n "$oc"; \
    install -m 0755 "$oc" /usr/local/bin/opencode; \
    rm -rf /tmp/oc; \
    opencode --version

RUN set -eux; \
    arch="$(uname -m)"; \
    case "$arch" in \
        x86_64) inst=Miniconda3-latest-Linux-x86_64.sh ;; \
        aarch64) inst=Miniconda3-latest-Linux-aarch64.sh ;; \
        *) echo "unsupported uname -m: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://repo.anaconda.com/miniconda/${inst}" -o /tmp/miniconda.sh; \
    bash /tmp/miniconda.sh -b -p /opt/miniconda3; \
    rm -f /tmp/miniconda.sh; \
    /opt/miniconda3/bin/conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main; \
    /opt/miniconda3/bin/conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r

# py_latest: Python 3.13. PyTorch / TensorFlow omitted — add via custom image if needed.
RUN /opt/miniconda3/bin/conda create -n py310 python=3.10 -y \
    && /opt/miniconda3/bin/conda create -n py312 python=3.12 -y \
    && /opt/miniconda3/bin/conda create -n py_latest python=3.13 -y

RUN set -eux; \
    for e in py310 py312 py_latest; do \
        /opt/miniconda3/bin/conda run -n "$e" python -m pip install --upgrade pip; \
        /opt/miniconda3/bin/conda run -n "$e" python -m pip install numpy pandas; \
    done; \
    /opt/miniconda3/bin/conda clean -afy

# Ubuntu base images often reserve UID 1000 for `ubuntu`; remove it so we can use `opencode`.
RUN if id ubuntu &>/dev/null; then userdel -r ubuntu; fi \
    && useradd -m -u 1000 -s /usr/bin/zsh opencode \
    && mkdir -p /workspace \
    && chown -R opencode:opencode /opt/miniconda3 /workspace /home/opencode

USER opencode
WORKDIR /home/opencode

# Rust stable (rustup) + conda for zsh; cargo env after conda block.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable \
    && . "$HOME/.cargo/env" \
    && rustc --version \
    && cargo --version \
    && /opt/miniconda3/bin/conda init zsh \
    && printf '\n. "$HOME/.cargo/env"\n' >> /home/opencode/.zshrc

USER root
COPY prefetch/rust /home/opencode/prefetch/rust
COPY prefetch/node /home/opencode/prefetch/node
RUN chown -R opencode:opencode /home/opencode/prefetch

USER opencode
# Populate Cargo/npm caches from lockfiles; then verify offline reinstall works (air-gapped dev).
RUN set -eux; \
    . "$HOME/.cargo/env"; \
    cd /home/opencode/prefetch/rust && cargo fetch --locked; \
    cd /home/opencode/prefetch/node && npm ci; \
    cd /home/opencode/prefetch/rust && CARGO_NET_OFFLINE=true cargo fetch --locked; \
    cd /home/opencode/prefetch/node && rm -rf node_modules && npm ci --offline

WORKDIR /workspace

USER opencode
ENTRYPOINT []
CMD ["/usr/bin/zsh", "-l"]
