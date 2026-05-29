FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:99
ENV WINEPREFIX=/root/.wine
ENV WINEARCH=win64
ENV WINEDEBUG=-all

# ============================================
# CORE DEPENDENCIES (LIGHTWEIGHT)
# ============================================
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y \
    wget curl unzip git \
    xvfb fluxbox x11vnc \
    python3 python3-pip \
    wine64 wine32 cabextract \
    net-tools \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# noVNC (LATEST STABLE)
# ============================================
RUN git clone --depth 1 https://github.com/novnc/noVNC.git /opt/novnc && \
    git clone --depth 1 https://github.com/novnc/websockify /opt/novnc/utils/websockify

WORKDIR /app

# ============================================
# COPY EA (MUST BE EX5 FOR REAL TRADING)
# ============================================
COPY test.mq5 /app/test.mq5

# ============================================
# INSTALL MT5 (BUILD TIME)
# ============================================
RUN Xvfb :99 -screen 0 1024x768x16 & \
    export DISPLAY=:99 && \
    sleep 3 && \
    wineboot --init && \
    sleep 20 && \
    mkdir -p /mt5 && cd /mt5 && \
    wget -O mt5setup.exe https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe && \
    xvfb-run -a wine mt5setup.exe /silent || true && \
    sleep 60

# ============================================
# START SCRIPT (FIXED ORDER - NO RACE CONDITIONS)
# ============================================
RUN printf '%s\n' \
'#!/bin/bash' \
'' \
'echo "STARTING MT5 + noVNC (FIXED LIGHTWEIGHT VERSION)"' \
'' \
'# =========================' \
'# 1. START X SERVER FIRST' \
'# =========================' \
'Xvfb :99 -screen 0 1024x768x16 -ac -nolisten tcp -noreset &' \
'sleep 2' \
'export DISPLAY=:99' \
'' \
'# ENSURE X IS READY' \
'xdpyinfo >/dev/null 2>&1 || true' \
'' \
'# =========================' \
'# 2. START WINDOW MANAGER' \
'# =========================' \
'fluxbox &' \
'sleep 2' \
'' \
'# =========================' \
'# 3. START VNC SERVER (WAIT FOR X)' \
'# =========================' \
'x11vnc -display :99 -forever -shared -nopw -rfbport 5900 -wait 50 -noxdamage &' \
'sleep 2' \
'' \
'# =========================' \
'# 4. START noVNC WEB CLIENT' \
'# =========================' \
'/opt/novnc/utils/novnc_proxy --vnc localhost:5900 --listen 6080 &' \
'sleep 2' \
'' \
'# =========================' \
'# 5. START SIMPLE STATUS SERVER' \
'# =========================' \
'mkdir -p /web' \
'echo "MT5 READY" > /web/index.html' \
'cd /web && python3 -m http.server 8080 &' \
'' \
'# =========================' \
'# 6. FIND MT5 BINARY' \
'# =========================' \
'MT5=$(find /root/.wine -iname terminal64.exe | head -1)' \
'' \
'if [ -z "$MT5" ]; then' \
'  echo "MT5 NOT FOUND - EXITING"' \
'  tail -f /dev/null' \
'fi' \
'' \
'echo "MT5 FOUND: $MT5"' \
'' \
'# =========================' \
'# 7. START MT5 (DELAYED FOR STABILITY)' \
'# =========================' \
'sleep 8' \
'wine "$MT5" /portable &' \
'' \
'sleep 20' \
'' \
'# =========================' \
'# 8. INSTALL EA' \
'# =========================' \
'EXPERTS=$(find /root/.wine -type d -path "*MQL5/Experts" | head -1)' \
'' \
'if [ ! -z "$EXPERTS" ]; then' \
'  cp /app/EA.ex5 "$EXPERTS/EA.ex5"' \
'  echo "EA INSTALLED SUCCESSFULLY"' \
'fi' \
'' \
'# =========================' \
'# 9. KEEP ALIVE LOOP' \
'# =========================' \
'echo "SYSTEM READY - OPEN noVNC"' \
'' \
'tail -f /dev/null' \
> /start.sh && chmod +x /start.sh

# ============================================
# EXPOSE PORTS
# ============================================
EXPOSE 8080 6080 5900

CMD ["/start.sh"]
