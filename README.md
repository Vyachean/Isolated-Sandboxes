# Isolated Sandboxes

**Purpose:** Quickly create partially-isolated sandboxes for running untrusted code (for example, AI agents). The project aims to reduce the risk of damaging the host and user data while keeping the environment convenient to use.

Main idea
- The main project file is [.justfile](.justfile). It contains all management recipes: building the image, creating containers, configuring the environment, and running user scripts inside a sandbox.
- Typical workflow: `just box name`. The recipes create a directory under `sandboxes/`, start a container with configured namespaces and resource limits, and run `setup.sh` inside the container as an unprivileged user.

Quick start (recommended commands)

```bash
just build-base     # build the base image (podman)
just box name       # create/start and enter a sandbox (replace name)
just ls             # list sandboxes
just rm name        # remove a sandbox
```

Key files
- [.justfile](.justfile) — main management script for sandboxes.
- [Containerfile](Containerfile) — Docker/Podman image used as the base.
- [setup.sh](setup.sh) — user script executed inside the container to initialize the environment.
- `sandboxes/` — directory containing sandbox instances and their data.

Security and limitations
- The goal is partial isolation: the setup uses techniques such as `--userns=keep-id`, resource limits, tmpfs for `XDG_RUNTIME_DIR`, and running user steps as an unprivileged user inside the container.
- However, some default flags in `.justfile` (for example, `--net=host`, `--ipc=host`, device passthrough) reduce the level of isolation. These flags are included for convenience and compatibility (graphics, audio, IPC), but they lower the guarantees against impact on the host.
- Recommendation: before using sandboxes for sensitive workloads, review and, if necessary, adjust flags in [.justfile](.justfile) (remove `--net=host`, `--ipc=host`, restrict device passthrough, etc.).

Usage recommendations
- Run each AI agent in a separate sandbox to limit the blast radius.
- Do not store secrets in `sandboxes/`.
- Inspect `.justfile` and `setup.sh` before running.
