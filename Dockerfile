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
    wine wine64 wine32:i386 winbind \
    xvfb fluxbox x11vnc \
    wget curl git unzip dos2unix procps \
    cabextract xdotool xterm net-tools \
    python3 python3-pip \
    xfonts-base xfonts-75dpi \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ============================================
# INSTALL LATEST noVNC + websockify
# ============================================
RUN git clone --depth 1 https://github.com/novnc/noVNC.git /opt/novnc && \
    git clone --depth 1 https://github.com/novnc/websockify.git /opt/novnc/utils/websockify

# ============================================
# FIX noVNC MOBILE addEventListener ERROR
# ============================================
RUN sed -i "s/const clipboardButton.*/const clipboardButton = document.getElementById('noVNC_clipboard_button') || null;/g" /opt/novnc/app/ui.js && \
    sed -i "s/clipboardButton.addEventListener(/clipboardButton \\&\\& clipboardButton.addEventListener(/g" /opt/novnc/app/ui.js && \
    sed -i "s/const clipboardClearButton.*/const clipboardClearButton = document.getElementById('noVNC_clipboard_clear_button') || null;/g" /opt/novnc/app/ui.js && \
    sed -i "s/clipboardClearButton.addEventListener(/clipboardClearButton \\&\\& clipboardClearButton.addEventListener(/g" /opt/novnc/app/ui.js

# ============================================
# PYTHON MT5 BRIDGE
# ============================================
RUN pip install --no-cache-dir mt5linux rpyc

# ============================================
# DOWNLOAD MT5 INSTALLER
# ============================================
RUN wget -q \
https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe \
-O /root/mt5setup.exe

# ============================================
# COPY EA
# ============================================
COPY test.mq5 /root/test.mq5

# ============================================
# ENTRYPOINT
# ============================================
RUN cat > /entrypoint.sh <<'EOF'
#!/bin/bash
set -e

echo "======================================="
echo "STARTING MT5 + noVNC"
echo "======================================="

# ========================================
# CLEAN OLD X11
# ========================================
rm -rf /tmp/.X* /tmp/.X11-unix

# ========================================
# START XVFB
# ========================================
Xvfb :1 -screen 0 1280x1024x24 -ac -noreset &
export DISPLAY=:1
sleep 3

# ========================================
# START FLUXBOX
# ========================================
fluxbox &
sleep 3

# ========================================
# OPEN TEST TERMINAL
# ========================================
xterm -geometry 100x30+10+10 &
sleep 2

# ========================================
# START X11VNC
# ========================================
x11vnc \
-display :1 \
-forever \
-shared \
-nopw \
-rfbport 5900 \
-noxdamage \
&
sleep 3

# ========================================
# START noVNC
# ========================================
/opt/novnc/utils/novnc_proxy \
--vnc localhost:5900 \
--listen 8080 \
&
sleep 5

# ========================================
# INIT WINE
# ========================================
wineboot --init
sleep 10

MT5_EXE="/root/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe"

# ========================================
# INSTALL MT5
# ========================================
if [ ! -f "$MT5_EXE" ]; then
    echo "Installing MT5..."
    wine /root/mt5setup.exe /auto
    sleep 90
fi

# ========================================
# VERIFY MT5 EXISTS
# ========================================
if [ ! -f "$MT5_EXE" ]; then
    echo "MT5 installation failed."
    find /root/.wine -iname "terminal64.exe"
    tail -f /dev/null
fi

echo "MT5 FOUND:"
echo "$MT5_EXE"

# ========================================
# START MT5
# ========================================
echo "Launching MT5..."
wine "$MT5_EXE" /portable &
sleep 30

# ========================================
# FIND MT5 DATA DIRECTORY
# ========================================
DATA_DIR=$(find /root/.wine -type d -path "*MetaQuotes/Terminal/*/MQL5" 2>/dev/null | head -n 1)

if [ -z "$DATA_DIR" ]; then
    DATA_DIR="/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5"
fi

echo "DATA DIR:"
echo "$DATA_DIR"

mkdir -p "$DATA_DIR/Experts"

# ========================================
# COPY EA
# ========================================
cp /root/test.mq5 "$DATA_DIR/Experts/" || true

echo "======================================="
echo "EA INSTALLED"
echo "======================================="

ls -la "$DATA_DIR/Experts/" || true

# ========================================
# START PYTHON BRIDGE
# ========================================
python3 -m mt5linux --host 0.0.0.0 --port 8001 &

echo "======================================="
echo "SYSTEM READY"
echo "======================================="
echo "OPEN:"
echo "/vnc.html?autoconnect=1&resize=remote"
echo "======================================="

# ========================================
# KEEP CONTAINER RUNNING
# ========================================
tail -f /dev/null

EOF

RUN chmod +x /entrypoint.sh && dos2unix /entrypoint.sh

# ============================================
# PORTS
# ============================================
EXPOSE 8080 8001

CMD ["/bin/bash", "/entrypoint.sh"]
