FROM registry.fedoraproject.org/fedora-toolbox:latest

RUN dnf install -y \
    nss \
    atk \
    at-spi2-atk \
    cups-libs \
    libdrm \
    libXcomposite \
    libXcursor \
    libXdamage \
    mesa-libgbm \
    alsa-lib \
    libxshmfence \
    libXrandr \
    google-noto-sans-fonts \
    git \
    curl \
    wget \
    unzip \
    zip \
    nano \
    findutils \
    iputils \
    hostname \
    sudo \
    shadow-utils \
    xorg-x11-xauth \
    which \
    pulseaudio-utils && \
    dnf clean all

RUN rpm --import https://packages.microsoft.com/keys/microsoft.asc
RUN echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | tee /etc/yum.repos.d/vscode.repo > /dev/null

RUN dnf install -y code

RUN curl -fsSL https://claude.ai/install.sh | bash