FROM python:3.11-slim-bookworm

USER root

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:1
ENV WINEPREFIX=/root/.wine
ENV WINEARCH=win64
ENV WINEDEBUG=-all

# ============================================
# SYSTEM
# ============================================
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    gnupg2 software-properties-common ca-certificates \
    wget curl git unzip dos2unix procps cabextract \
    xvfb fluxbox x11vnc net-tools xdotool \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# LATEST WINEHQ
# ============================================
RUN mkdir -pm755 /etc/apt/keyrings && \
    wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key && \
    wget -NP /etc/apt/sources.list.d/ \
    https://dl.winehq.org/wine-builds/debian/dists/bookworm/winehq-bookworm.sources && \
    apt-get update && \
    apt-get install -y --install-recommends winehq-stable

# ============================================
# LATEST noVNC
# ============================================
RUN git clone --depth 1 https://github.com/novnc/noVNC.git /opt/novnc && \
    git clone --depth 1 https://github.com/novnc/websockify /opt/novnc/utils/websockify

# ============================================
# PYTHON BRIDGE
# ============================================
RUN pip install --no-cache-dir mt5linux rpyc

# ============================================
# DOWNLOAD MT5
# ============================================
RUN wget -q \
https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe \
-O /root/mt5setup.exe

# ============================================
# COPY EA (USE EX5 ONLY)
# ============================================
COPY ["test.mq5", "/root/test.mq5"]

# ============================================
# INSTALL MT5 DURING BUILD (IMPORTANT FIX)
# ============================================
RUN Xvfb :1 -screen 0 1280x1024x24 -ac & \
    export DISPLAY=:1 && \
    sleep 5 && \
    wineboot --init && \
    sleep 15 && \
    xvfb-run -a wine /root/mt5setup.exe /silent || true && \
    sleep 60

# ============================================
# ENTRYPOINT
# ============================================
RUN cat > /entrypoint.sh <<'EOF'
#!/bin/bash
set -e

echo "======================================="
echo "MT5 + noVNC STARTING"
echo "======================================="

rm -rf /tmp/.X*

# ========================================
# XVFB
# ========================================
Xvfb :1 -screen 0 1280x1024x24 -ac +extension GLX +render -noreset &
export DISPLAY=:1

sleep 3

# ========================================
# FLUXBOX
# ========================================
fluxbox &
sleep 2

# ========================================
# X11VNC
# ========================================
x11vnc \
-display :1 \
-forever \
-shared \
-nopw \
-rfbport 5900 \
-wait 50 \
-noxdamage \
&
sleep 2

# ========================================
# noVNC
# ========================================
/opt/novnc/utils/novnc_proxy \
--vnc localhost:5900 \
--listen 8080 \
&
sleep 3

# ========================================
# FIND MT5
# ========================================
MT5_EXE=$(find /root/.wine -iname terminal64.exe | head -1)

if [ -z "$MT5_EXE" ]; then
    echo "MT5 NOT FOUND"
    tail -f /dev/null
fi

echo "MT5 FOUND:"
echo "$MT5_EXE"

# ========================================
# START MT5
# ========================================
wine "$MT5_EXE" /portable &
sleep 25

# ========================================
# INSTALL EA
# ========================================
DATA_DIR=$(find /root/.wine -type d -path "*MQL5" | head -n 1)

if [ -z "$DATA_DIR" ]; then
    DATA_DIR="/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5"
fi

mkdir -p "$DATA_DIR/Experts"

cp /root/test.mq5 "$DATA_DIR/Experts/"

echo "EA INSTALLED"

ls -la "$DATA_DIR/Experts"

# ========================================
# PYTHON BRIDGE
# ========================================
python3 -m mt5linux --host 0.0.0.0 --port 8001 &

echo "======================================="
echo "SYSTEM READY"
echo "Open:"
echo "/vnc_lite.html"
echo "======================================="

tail -f /dev/null

EOF

RUN chmod +x /entrypoint.sh && dos2unix /entrypoint.sh

EXPOSE 8080 8001

CMD ["/bin/bash", "/entrypoint.sh"]
