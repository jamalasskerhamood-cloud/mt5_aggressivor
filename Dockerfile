FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:99
ENV WINEPREFIX=/root/.wine
ENV WINEARCH=win64
ENV WINEDEBUG=-all

# ============================================
# SYSTEM DEPENDENCIES
# ============================================
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y \
    wget curl unzip git \
    xvfb x11vnc fluxbox \
    python3 python3-pip \
    net-tools \
    wine64 wine32 cabextract \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# noVNC (LATEST FROM GITHUB)
# ============================================
RUN mkdir -p /opt/novnc && \
    git clone https://github.com/novnc/noVNC.git /opt/novnc && \
    git clone https://github.com/novnc/websockify /opt/novnc/utils/websockify

# ============================================
# WORKDIR
# ============================================
WORKDIR /app

# ============================================
# COPY EA (MUST BE .EX5 FOR REAL TRADING)
# ============================================
COPY test.mq5 /app/test.mq5

# ============================================
# INSTALL MT5 DURING BUILD
# ============================================
RUN Xvfb :99 -screen 0 1024x768x16 & \
    export DISPLAY=:99 && \
    sleep 5 && \
    wineboot --init && \
    sleep 20 && \
    mkdir -p /mt5 && cd /mt5 && \
    wget -O mt5setup.exe https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe && \
    xvfb-run -a wine mt5setup.exe /silent || true && \
    sleep 60

# ============================================
# START SCRIPT (FULL DESKTOP + NOVNC)
# ============================================
RUN printf '%s\n' \
'#!/bin/bash' \
'' \
'echo "========================================"' \
'echo "   MT5 + noVNC DESKTOP STARTING"' \
'echo "========================================"' \
'' \
'# START VIRTUAL DISPLAY' \
'Xvfb :99 -screen 0 1024x768x16 -ac +extension GLX +render -noreset &' \
'export DISPLAY=:99' \
'sleep 3' \
'' \
'# START WINDOW MANAGER' \
'fluxbox &' \
'sleep 2' \
'' \
'# START VNC SERVER (SHARES DISPLAY)' \
'x11vnc -display :99 -forever -shared -nopw -rfbport 5900 &' \
'sleep 2' \
'' \
'# START noVNC WEB CLIENT' \
'/opt/novnc/utils/novnc_proxy --vnc localhost:5900 --listen 6080 &' \
'sleep 2' \
'' \
'# START SIMPLE WEB SERVER (HEALTH CHECK)' \
'mkdir -p /web' \
'echo "MT5 + noVNC Running" > /web/index.html' \
'cd /web' \
'python3 -m http.server 8080 &' \
'' \
'# FIND MT5' \
'MT5=$(find /root/.wine -iname terminal64.exe | head -1)' \
'' \
'if [ -z "$MT5" ]; then' \
'  echo "MT5 NOT FOUND"' \
'  tail -f /dev/null' \
'fi' \
'' \
'echo "MT5 FOUND: $MT5"' \
'' \
'# START MT5' \
'wine "$MT5" /portable &' \
'sleep 25' \
'' \
'# INSTALL EA' \
'EXPERTS=$(find /root/.wine -type d -path "*MQL5/Experts" | head -1)' \
'' \
'if [ ! -z "$EXPERTS" ]; then' \
'  cp /app/EA.ex5 "$EXPERTS/QuantumShield.ex5"' \
'  echo "EA INSTALLED"' \
'fi' \
'' \
'echo "========================================"' \
'echo "DESKTOP READY"' \
'echo "OPEN: http://YOUR-RAILWAY-URL:6080/vnc.html"' \
'echo "========================================"' \
'' \
'tail -f /dev/null' \
> /start.sh && chmod +x /start.sh

# ============================================
# PORTS
# ============================================
EXPOSE 8080 6080 5900

CMD ["/start.sh"]
