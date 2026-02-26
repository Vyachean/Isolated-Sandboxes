# === Settings ===
custom_image := "sandbox-base"
dockerfile   := "Containerfile"
# Storage for sandboxes
root_dir     := justfile_directory() / "sandboxes"
user_name    := "sandbox"
prefix       := "box-"

# Host system variables
uid      := `id -u`
run_dir  := "/run/user/" + uid

# Helpers for Podman templates
lb := "{{"
rb := "}}"

# === Commands ===
default:
    @just --list

# Build base image
build-base:
    @echo "Checking/Building base image {{custom_image}}..."
    podman build -t {{custom_image}} -f {{dockerfile}} .

# Enter or create a sandbox
box name:
    #!/usr/bin/env bash
    set -e
    full_name="{{prefix}}{{name}}"
    
    if ! podman container exists "$full_name"; then
        just build-base
        just _box-create "{{name}}"
    fi

    # Ensure container is running
    status=$(podman container inspect -f '{{lb}}.State.Status{{rb}}' "$full_name")
    if [ "$status" != "running" ]; then
        echo "Starting '$full_name'..."
        podman start "$full_name"
    fi

    # Fix: Restore ownership of tmpfs (run_dir) on every entry to keep DBus/Wayland writable
    podman exec -u 0 "$full_name" chown {{uid}}:{{uid}} {{run_dir}}
    
    podman exec -it \
        -e TERM=xterm-256color \
        -u "{{user_name}}" \
        -w "/home/{{user_name}}" \
        "$full_name" /bin/bash

# Remove a sandbox
rm name:
    @echo "Removing sandbox '{{name}}'..."
    @podman stop "{{prefix}}{{name}}" 2>/dev/null || true
    @podman rm -f "{{prefix}}{{name}}" 2>/dev/null || true

# List all sandboxes
ls:
    @podman ps -a --filter "name={{prefix}}" --format "table {{lb}}.Names{{rb}}\t{{lb}}.Status{{rb}}\t{{lb}}.Image{{rb}}" | sed 's/{{prefix}}//g'

# --- Internal recipes ---

[private]
_box-create name:
    #!/usr/bin/env bash
    set -e
    box_path="{{root_dir}}/{{prefix}}{{name}}"
    mkdir -p "$box_path"
    
    # Resource limits (80% of host capacity)
    mem_limit=$(awk '/MemTotal/ {print int($2*0.8/1024)}' /proc/meminfo)
    cpu_limit=$(nproc | awk '{print $1*0.8}')

    echo "Creating '{{name}}' (RAM: ${mem_limit}MB, CPU: ${cpu_limit})..."

    # Mounts: tmpfs for XDG_RUNTIME_DIR and sockets
    mounts="--mount type=tmpfs,destination={{run_dir}},tmpfs-mode=0700"
    
    # 1. Wayland support (Native only)
    if [ -n "$WAYLAND_DISPLAY" ] && [ -e "{{run_dir}}/$WAYLAND_DISPLAY" ]; then
        mounts="$mounts -v {{run_dir}}/$WAYLAND_DISPLAY:{{run_dir}}/$WAYLAND_DISPLAY:ro"
    fi
    
    # 2. DBus for Notifications (RW required)
    if [ -e "{{run_dir}}/bus" ]; then
        mounts="$mounts -v {{run_dir}}/bus:{{run_dir}}/bus"
    fi

    # 3. Sound support
    if [ -e "{{run_dir}}/pipewire-0" ]; then
        mounts="$mounts -v {{run_dir}}/pipewire-0:{{run_dir}}/pipewire-0:ro"
    fi

    podman run -d \
        --name "{{prefix}}{{name}}" \
        --hostname "{{name}}" \
        --security-opt label=disable \
        --userns=keep-id \
        --ipc=host \
        --net=host \
        --device /dev/dri --device /dev/snd \
        --memory "${mem_limit}m" --cpus "$cpu_limit" \
        --pids-limit=4096 \
        -e WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
        -e XDG_RUNTIME_DIR="{{run_dir}}" \
        -e DBUS_SESSION_BUS_ADDRESS="unix:path={{run_dir}}/bus" \
        -v /etc/localtime:/etc/localtime:ro \
        -v "$box_path":/home/{{user_name}}:Z \
        $mounts \
        {{custom_image}} tail -f /dev/null
    
    just _box-setup "{{prefix}}{{name}}"

[private]
_box-setup container:
    #!/usr/bin/env bash
    # 1. System-level setup
    podman exec -u 0 "{{container}}" bash -c "
        orig_user=\$(getent passwd {{uid}} | cut -d: -f1)
        
        if [ -n \"\$orig_user\" ] && [ \"\$orig_user\" != \"{{user_name}}\" ]; then
            groupmod -n {{user_name}} \"\$orig_user\" 2>/dev/null || true
            usermod -l {{user_name}} -d /home/{{user_name}} \"\$orig_user\"
        elif [ -z \"\$orig_user\" ]; then
            useradd -m -u {{uid}} {{user_name}}
        fi
        
        echo '{{user_name}} ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
        
        # VS Code wrapper (Strict Wayland)
        mkdir -p /home/{{user_name}}/.local/bin
        echo '#!/usr/bin/env bash' > /home/{{user_name}}/.local/bin/code
        echo '/usr/bin/code --no-sandbox --enable-features=UseOzonePlatform --ozone-platform=wayland \"\$@\"' >> /home/{{user_name}}/.local/bin/code
        chmod +x /home/{{user_name}}/.local/bin/code
        chown -R {{uid}}:{{uid}} /home/{{user_name}}/.local
        
        # Shell environment setup
        if ! grep -q '.local/bin' /home/{{user_name}}/.bashrc 2>/dev/null; then
            echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> /home/{{user_name}}/.bashrc
            echo 'export PS1=\"\\[\\e[1;32m\\][📦 {{container}}] \\[\\e[1;34m\\]\\u@\\h:\\w$ \\[\\e[0m\\]\"' >> /home/{{user_name}}/.bashrc
            chown {{uid}}:{{uid}} /home/{{user_name}}/.bashrc
        fi
    "

    # 2. User-level setup
    if [ -f "setup.sh" ]; then
        echo "Running custom setup script (setup.sh)..."
        podman exec -i -u "{{user_name}}" "{{container}}" bash < setup.sh
    fi
