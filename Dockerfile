FROM python:3.12-slim-bookworm

USER root

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:1
ENV WINEPREFIX=/root/.wine
ENV WINEARCH=win64
ENV WINEDEBUG=-all

# Install latest system packages
RUN dpkg --add-architecture i386 && apt-get update && apt-get install -y --no-install-recommends \
    wine wine64 wine32:i386 winbind \
    xvfb fluxbox x11vnc novnc websockify \
    wget curl procps cabextract unzip dos2unix xdotool \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Update pip and install latest Python packages
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir mt5linux==0.1.6 rpyc==6.0.0

# Download latest MT5 setup
RUN wget -q --no-check-certificate \
    https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe \
    -O /root/mt5setup.exe

# Copy EA files
COPY ["test.mq5", "/root/test.mq5"]

# Create entrypoint script with latest noVNC path
RUN cat > /entrypoint.sh <<'EOF'
#!/bin/bash
set -e

echo "========================================="
echo "MT5 Aggressor - Starting up..."
echo "========================================="

rm -rf /tmp/.X*

# Start Xvfb (Virtual Framebuffer)
Xvfb :1 -screen 0 1280x1024x24 -ac &
sleep 2

# Start Fluxbox (Window Manager)
fluxbox &

# Start x11vnc (VNC Server)
x11vnc -display :1 -forever -shared -nopw -rfbport 5900 &

# Start websockify (WebSocket to VNC bridge)
# Use the correct noVNC path
websockify --web=/usr/share/novnc 8080 0.0.0.0:5900 &

# Initialize Wine
wineboot --init
sleep 5

MT5_EXE="/root/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe"

# Install MT5 if not present
if [ ! -f "$MT5_EXE" ]; then
    echo "Installing MetaTrader 5..."
    wine /root/mt5setup.exe /auto
    sleep 90
fi

# Launch MT5
echo "Launching MetaTrader 5..."
wine "$MT5_EXE" &
sleep 30

# Find MT5 data directory
DATA_DIR=$(find /root/.wine -type d -path "*MetaQuotes/Terminal/*/MQL5" 2>/dev/null | head -n 1)

if [ -z "$DATA_DIR" ]; then
    DATA_DIR="/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5"
fi

# Copy EA to Experts folder
mkdir -p "$DATA_DIR/Experts"
cp "/root/test.mq5" "$DATA_DIR/Experts/"

echo "========================================="
echo "✅ EA Copied to: $DATA_DIR/Experts/"
echo "========================================="
ls -la "$DATA_DIR/Experts/"

# Start Python MT5 Bridge
echo "Starting Python MT5 bridge on port 8001..."
python3 -m mt5linux --host 0.0.0.0 --port 8001 &

echo "========================================="
echo "✅ MT5 Aggressor is ready!"
echo "========================================="
echo "Access VNC at: http://localhost:8080/vnc.html"
echo "MT5 Bridge at: port 8001"
echo "========================================="

# Keep container running
tail -f /dev/null
EOF

RUN chmod +x /entrypoint.sh && dos2unix /entrypoint.sh

EXPOSE 8080 8001

CMD ["/bin/bash", "/entrypoint.sh"]
