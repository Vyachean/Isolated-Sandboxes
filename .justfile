# === Настройки ===
custom_image := "sandbox-base"
dockerfile   := "Containerfile"
# Директория создается рядом с файлом .justfile
root_dir     := justfile_directory() / "sandboxes"
user_name    := "sandbox"
prefix       := "box-"

# Системные переменные
uid      := `id -u`
run_dir  := "/run/user/" + uid

# Хелперы для экранирования скобок в шаблонах Podman
lb := "{{"
rb := "}}"

# === Команды ===
default:
    @just --list

# Сборка базового образа (использует кэш Podman автоматически)
build-base:
    @echo "Checking/Building base image {{custom_image}}..."
    podman build -t {{custom_image}} -f {{dockerfile}} .

# Вход в песочницу
box name:
    #!/usr/bin/env bash
    set -e
    full_name="{{prefix}}{{name}}"
    
    if ! podman container exists "$full_name"; then
        # Всегда вызываем билд перед созданием: если Containerfile не менялся, подхватится кэш
        just build-base
        just _box-create "{{name}}"
    fi

    # Проверка статуса
    status=$(podman container inspect -f '{{lb}}.State.Status{{rb}}' "$full_name")
    if [ "$status" != "running" ]; then
        echo "Starting '$full_name'..."
        podman start "$full_name"
    fi
    
    podman exec -it \
        -e TERM=xterm-256color \
        -u "{{user_name}}" \
        -w "/home/{{user_name}}" \
        "$full_name" /bin/bash

# Удаление песочницы
rm name:
    @echo "Removing sandbox '{{name}}'..."
    @podman stop "{{prefix}}{{name}}" 2>/dev/null || true
    @podman rm -f "{{prefix}}{{name}}" 2>/dev/null || true

# Список песочниц
ls:
    @podman ps -a --filter "name={{prefix}}" --format "table {{lb}}.Names{{rb}}\t{{lb}}.Status{{rb}}\t{{lb}}.Image{{rb}}" | sed 's/{{prefix}}//g'

# --- Внутренние рецепты (скрытые) ---

[private]
_box-create name:
    #!/usr/bin/env bash
    set -e
    box_path="{{root_dir}}/{{prefix}}{{name}}"
    mkdir -p "$box_path"
    
    # Лимиты (80% от системы)
    mem_limit=$(awk '/MemTotal/ {print int($2*0.8/1024)}' /proc/meminfo)
    cpu_limit=$(nproc | awk '{print $1*0.8}')

    echo "Creating '{{name}}' (RAM: ${mem_limit}MB, CPU: ${cpu_limit})..."

    # Сборка монтирований
    mounts="--mount type=tmpfs,destination={{run_dir}},tmpfs-mode=0700"
    
    if [ -n "$WAYLAND_DISPLAY" ] && [ -e "{{run_dir}}/$WAYLAND_DISPLAY" ]; then
        mounts="$mounts -v {{run_dir}}/$WAYLAND_DISPLAY:{{run_dir}}/$WAYLAND_DISPLAY:ro"
    fi
    [ -e "{{run_dir}}/bus" ] && mounts="$mounts -v {{run_dir}}/bus:{{run_dir}}/bus:ro"
    [ -e "{{run_dir}}/pipewire-0" ] && mounts="$mounts -v {{run_dir}}/pipewire-0:{{run_dir}}/pipewire-0:ro"

    podman run -d \
        --name "{{prefix}}{{name}}" \
        --hostname "{{name}}" \
        --security-opt label=disable \
        --userns=keep-id \
        --ipc=host --net=host \
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
    # 1. Настройка системы от имени root
    podman exec -u 0 "{{container}}" bash -c "
        orig_user=\$(getent passwd {{uid}} | cut -d: -f1)
        
        if [ -n \"\$orig_user\" ] && [ \"\$orig_user\" != \"{{user_name}}\" ]; then
            groupmod -n {{user_name}} \"\$orig_user\" 2>/dev/null || true
            usermod -l {{user_name}} -d /home/{{user_name}} \"\$orig_user\"
        elif [ -z \"\$orig_user\" ]; then
            useradd -m -u {{uid}} {{user_name}}
        fi
        
        echo '{{user_name}} ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
        chown {{uid}}:{{uid}} {{run_dir}} && chmod 700 {{run_dir}}
        
        # Безопасная настройка .bashrc (добавление пути и промпта)
        if ! grep -q '.local/bin' /home/{{user_name}}/.bashrc 2>/dev/null; then
            echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> /home/{{user_name}}/.bashrc
            echo 'export PS1=\"\[\e[1;32m\][📦 {{container}}] \[\e[1;34m\]\u@\h:\w$ \[\e[0m\]\"' >> /home/{{user_name}}/.bashrc
            chown {{uid}}:{{uid}} /home/{{user_name}}/.bashrc
        fi
    "

    # 2. Выполнение пользовательского скрипта настройки
    if [ -f "setup.sh" ]; then
        echo "Running custom setup script (setup.sh)..."
        podman exec -i -u "{{user_name}}" "{{container}}" bash < setup.sh
    else
        echo "setup.sh not found, skipping user configuration."
    fi