FROM ubuntu:22.04

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
    python3 && \
    rm -rf /var/lib/apt/lists/*

# ============================================
# WORKDIR
# ============================================
WORKDIR /app

# ============================================
# COPY EA
# ============================================
COPY test.mq5 /app/test.mq5

# ============================================
# START SCRIPT
# ============================================
RUN printf '#!/bin/bash\n\
set -e\n\
\n\
echo "Starting virtual display..."\n\
Xvfb :99 -screen 0 1024x768x16 &\n\
sleep 3\n\
\n\
echo "Initializing Wine..."\n\
wineboot --init || true\n\
sleep 5\n\
\n\
mkdir -p /mt5\n\
cd /mt5\n\
\n\
echo "Downloading MT5..."\n\
wget -q -O mt5setup.exe https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe\n\
\n\
echo "Installing MT5..."\n\
wine mt5setup.exe /silent || true\n\
sleep 15\n\
\n\
echo "Copying EA..."\n\
find /root/.wine -type d -name Experts | head -1 | xargs -I {} cp /app/test.mq5 "{}/test.mq5" || true\n\
\n\
echo "Starting lightweight web server..."\n\
cd /app\n\
echo "MT5 Aggressivor Running" > index.html\n\
python3 -m http.server 8080 &\n\
\n\
echo "Container ready."\n\
tail -f /dev/null\n' > /start.sh && chmod +x /start.sh

# ============================================
# EXPOSE PORT
# ============================================
EXPOSE 8080

CMD ["/start.sh"]
