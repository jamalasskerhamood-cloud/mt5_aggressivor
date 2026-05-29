FROM python:3.11-slim-bookworm

USER root

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:1
ENV WINEPREFIX=/root/.wine
ENV WINEARCH=win64
ENV WINEDEBUG=-all

# ============================================
# INSTALL SYSTEM
# ============================================
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    wget curl git unzip dos2unix procps cabextract \
    xvfb fluxbox x11vnc net-tools xdotool \
    x11-apps xterm feh \
    python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# INSTALL WINEHQ
# ============================================
RUN mkdir -pm755 /etc/apt/keyrings && \
    wget -O /etc/apt/keyrings/winehq-archive.key \
    https://dl.winehq.org/wine-builds/winehq.key && \
    wget -NP /etc/apt/sources.list.d/ \
    https://dl.winehq.org/wine-builds/debian/dists/bookworm/winehq-bookworm.sources && \
    apt-get update && \
    apt-get install -y --install-recommends winehq-stable

# ============================================
# INSTALL noVNC
# ============================================
RUN git clone --depth 1 https://github.com/novnc/noVNC.git /opt/novnc && \
    git clone --depth 1 https://github.com/novnc/websockify /opt/novnc/utils/websockify

# ============================================
# PYTHON MT5 BRIDGE
# ============================================
RUN pip install --no-cache-dir mt5linux rpyc

# ============================================
# DOWNLOAD MT5
# ============================================
RUN wget -q \
https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe \
-O /root/mt5setup.exe

# ============================================
# COPY MQ5
# ============================================
COPY ["test.mq5", "/root/test.mq5"]

# ============================================
# INSTALL MT5 DURING BUILD
# ============================================
RUN Xvfb :1 -screen 0 1280x1024x24 -ac & \
    export DISPLAY=:1 && \
    sleep 5 && \
    fluxbox & \
    sleep 5 && \
    wineboot --init && \
    sleep 20 && \
    wine /root/mt5setup.exe /silent || true && \
    sleep 120

# ============================================
# ENTRYPOINT
# ============================================
RUN cat > /entrypoint.sh <<'EOF'
#!/bin/bash

export DISPLAY=:1

echo "=================================="
echo "STARTING MT5 + FLUXBOX + NOVNC"
echo "=================================="

rm -rf /tmp/.X*

# ============================================
# START XVFB
# ============================================
Xvfb :1 \
-screen 0 1280x1024x24 \
-ac \
-noreset \
&
sleep 5

# ============================================
# START FLUXBOX
# ============================================
fluxbox &
sleep 5

# ============================================
# SET DESKTOP BACKGROUND
# ============================================
xsetroot -solid "#202020"

# ============================================
# OPEN TEST TERMINAL
# ============================================
xterm -geometry 120x30+50+50 &
sleep 3

# ============================================
# START X11VNC
# ============================================
x11vnc \
-display :1 \
-forever \
-shared \
-nopw \
-rfbport 5900 \
&
sleep 5

# ============================================
# START NOVNC
# ============================================
/opt/novnc/utils/novnc_proxy \
--vnc localhost:5900 \
--listen 8080 \
&
sleep 5

# ============================================
# FIND MT5
# ============================================
MT5_EXE=$(find /root/.wine -iname terminal64.exe | head -1)

echo "MT5:"
echo "$MT5_EXE"

# ============================================
# START MT5
# ============================================
if [ ! -z "$MT5_EXE" ]; then
    wine "$MT5_EXE" /portable &
fi

sleep 25

# ============================================
# FIND MQL5 FOLDER
# ============================================
DATA_DIR=$(find /root/.wine -type d -path "*MQL5" | head -1)

if [ -z "$DATA_DIR" ]; then
    DATA_DIR="/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5"
fi

mkdir -p "$DATA_DIR/Experts"

# ============================================
# COPY MQ5
# ============================================
cp /root/test.mq5 "$DATA_DIR/Experts/"

echo "=================================="
echo "EA COPIED"
echo "$DATA_DIR/Experts"
echo "=================================="

ls -la "$DATA_DIR/Experts"

# ============================================
# START MT5 PYTHON BRIDGE
# ============================================
python3 -m mt5linux --host 0.0.0.0 --port 8001 &

echo "=================================="
echo "SYSTEM READY"
echo "OPEN:"
echo "/vnc_lite.html"
echo "=================================="

tail -f /dev/null

EOF

RUN chmod +x /entrypoint.sh && dos2unix /entrypoint.sh

EXPOSE 8080 8001

CMD ["/bin/bash", "/entrypoint.sh"]
