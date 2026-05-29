FROM lscr.io/linuxserver/webtop:ubuntu-xfce

ENV DEBIAN_FRONTEND=noninteractive
ENV TITLE=MT5
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
    p7zip-full \
    wine64 \
    wine32 && \
    rm -rf /var/lib/apt/lists/*

# ============================================
# CREATE DIRECTORIES
# ============================================
RUN mkdir -p /mt5

RUN mkdir -p "/config/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Experts"

# ============================================
# DOWNLOAD MT5
# ============================================
RUN wget -O /mt5/mt5setup.exe \
https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe

# ============================================
# INIT WINE
# ============================================
RUN wineboot --init || true

RUN sleep 15

# ============================================
# INSTALL MT5
# ============================================
RUN xvfb-run wine /mt5/mt5setup.exe /silent || true

RUN sleep 20

# ============================================
# COPY EA (THIS IS THE FIX)
# ============================================
COPY ["test.mq5", "/config/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Experts/test.mq5"]

# ============================================
# AUTOSTART MT5
# ============================================
RUN mkdir -p /config/.config/autostart

RUN printf '%s\n' \
'[Desktop Entry]' \
'Type=Application' \
'Exec=wine "/config/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe"' \
'Hidden=false' \
'NoDisplay=false' \
'X-GNOME-Autostart-enabled=true' \
'Name=MT5' \
> /config/.config/autostart/mt5.desktop

# ============================================
# PORT
# ============================================
EXPOSE 3000

# ============================================
# HEALTHCHECK
# ============================================
HEALTHCHECK CMD pgrep wineserver || exit 1
