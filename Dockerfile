FROM ubuntu:22.04

# ============================================
# ENVIRONMENT
# ============================================
ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:99
ENV WINEPREFIX=/root/.wine
ENV WINEARCH=win64
ENV WINEDEBUG=-all

# ============================================
# INSTALL LIGHTWEIGHT DEPENDENCIES
# ============================================
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y \
    wget \
    curl \
    xvfb \
    wine64 \
    wine32 \
    cabextract \
    unzip \
    python3 \
    procps && \
    rm -rf /var/lib/apt/lists/*

# ============================================
# WORKDIR
# ============================================
WORKDIR /app

# ============================================
# COPY EA FILE
# ============================================
COPY test.mq5 /app/test.mq5

# ============================================
# CREATE START SCRIPT
# ============================================
RUN printf '#!/bin/bash\n\
set -e\n\
\n\
echo "=================================="\n\
echo "Starting MT5 Aggressivor Container"\n\
echo "=================================="\n\
\n\
# ====================================\n\
# START VIRTUAL DISPLAY\n\
# ====================================\n\
echo "Starting Xvfb..."\n\
Xvfb :99 -screen 0 1024x768x16 &\n\
sleep 3\n\
\n\
# ====================================\n\
# INITIALIZE WINE\n\
# ====================================\n\
echo "Initializing Wine..."\n\
wineboot --init || true\n\
sleep 5\n\
\n\
# ====================================\n\
# DOWNLOAD MT5 INSTALLER\n\
# ====================================\n\
mkdir -p /mt5\n\
cd /mt5\n\
\n\
echo "Downloading MetaTrader 5..."\n\
wget -q -O mt5setup.exe https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe\n\
\n\
# ====================================\n\
# INSTALL MT5\n\
# ====================================\n\
echo "Installing MT5 silently..."\n\
wine mt5setup.exe /silent || true\n\
\n\
echo "Waiting for installation..."\n\
sleep 30\n\
\n\
# ====================================\n\
# FIND MT5 TERMINAL\n\
# ====================================\n\
echo "Searching for terminal64.exe..."\n\
MT5_PATH=$(find /root/.wine -iname terminal64.exe | head -1)\n\
\n\
echo "MT5 Path: $MT5_PATH"\n\
\n\
# ====================================\n\
# COPY EA TO EXPERTS FOLDER\n\
# ====================================\n\
echo "Copying EA..."\n\
EXPERTS_DIR=$(find /root/.wine -type d -name Experts | head -1)\n\
\n\
if [ -n "$EXPERTS_DIR" ]; then\n\
    cp /app/test.mq5 "$EXPERTS_DIR/test.mq5" || true\n\
    echo "EA copied to: $EXPERTS_DIR"\n\
else\n\
    echo "Experts folder not found!"\n\
fi\n\
\n\
# ====================================\n\
# LAUNCH MT5\n\
# ====================================\n\
if [ -n "$MT5_PATH" ]; then\n\
    echo "Launching MT5..."\n\
    wine "$MT5_PATH" &\n\
else\n\
    echo "MT5 executable not found!"\n\
fi\n\
\n\
# ====================================\n\
# START WEB SERVER FOR RAILWAY\n\
# ====================================\n\
echo "Creating status page..."\n\
mkdir -p /app/web\n\
\n\
echo "<html><body style=\"background:black;color:lime;font-family:Arial;padding:20px;\"><h1>MT5 Aggressivor Running</h1><p>MetaTrader 5 running inside Railway container.</p></body></html>" > /app/web/index.html\n\
\n\
cd /app/web\n\
\n\
echo "Starting HTTP server on port 8080..."\n\
python3 -m http.server 8080 &\n\
\n\
# ====================================\n\
# SHOW RUNNING PROCESSES\n\
# ====================================\n\
echo "=================================="\n\
echo "Running Processes:"\n\
ps aux | grep wine || true\n\
echo "=================================="\n\
echo "Container Ready."\n\
echo "=================================="\n\
\n\
# KEEP CONTAINER ALIVE\n\
tail -f /dev/null\n' > /start.sh && chmod +x /start.sh

# ============================================
# EXPOSE PORT
# ============================================
EXPOSE 8080

# ============================================
# START CONTAINER
# ============================================
CMD ["/start.sh"]
