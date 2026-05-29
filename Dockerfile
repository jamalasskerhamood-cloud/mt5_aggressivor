FROM lscr.io/linuxserver/webtop:ubuntu-xfce

# ============================================
# ENVIRONMENT
# ============================================
ENV DEBIAN_FRONTEND=noninteractive
ENV TITLE=MT5-KASM
ENV DISPLAY=:1
ENV WINEPREFIX=/config/.wine
ENV WINEARCH=win64
ENV WINEDEBUG=-all

# ============================================
# INSTALL DEPENDENCIES
# ============================================
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y \
    wget \
    curl \
    unzip \
    xvfb \
    cabextract \
    winbind \
    net-tools \
    procps \
    p7zip-full \
    software-properties-common \
    wine64 \
    wine32 \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# CREATE DIRECTORIES
# ============================================
RUN mkdir -p /mt5

RUN mkdir -p /config/.wine

RUN mkdir -p /config/.wine/drive_c/Program\ Files/MetaTrader\ 5/MQL5/Experts

# ============================================
# DOWNLOAD MT5
# ============================================
RUN wget https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe \
    -O /mt5/mt5setup.exe

# ============================================
# INITIALIZE WINE
# ============================================
RUN wineboot --init || true

RUN sleep 20

# ============================================
# INSTALL MT5
# ============================================
RUN xvfb-run wine /mt5/mt5setup.exe /silent || true

RUN sleep 30

# ============================================
# COPY YOUR EA
# ============================================
COPY test.mq5 /config/.wine/drive_c/Program\ Files/MetaTrader\ 5/MQL5/Experts/test.mq5

# ============================================
# AUTOSTART MT5
# ============================================
RUN mkdir -p /config/.config/autostart

RUN printf '[Desktop Entry]\n\
Type=Application\n\
Exec=wine "/config/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe"\n\
Hidden=false\n\
NoDisplay=false\n\
X-GNOME-Autostart-enabled=true\n\
Name=MT5\n' \
> /config/.config/autostart/mt5.desktop

# ============================================
# OPTIONAL HEALTHCHECK
# ============================================
HEALTHCHECK --interval=30s --timeout=10s CMD pgrep wineserver || exit 1

# ============================================
# EXPOSE PORT
# ============================================
EXPOSE 3000
