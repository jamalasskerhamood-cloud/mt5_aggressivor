FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:99
ENV WINEPREFIX=/root/.wine
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
    x11vnc \
    fluxbox \
    wine64 \
    wine32 \
    cabextract \
    python3 \
    python3-pip \
    net-tools && \
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
# PRE-INSTALL MT5 DURING BUILD
# ============================================
RUN Xvfb :99 -screen 0 1024x768x16 & \
    sleep 5 && \
    wineboot --init && \
    sleep 15 && \
    mkdir -p /mt5 && \
    cd /mt5 && \
    wget -O mt5setup.exe https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe && \
    wine mt5setup.exe /silent || true && \
    sleep 60

# ============================================
# START SCRIPT
# ============================================
RUN printf '#!/bin/bash\n\
echo "=================================="\n\
echo "Starting MT5 Aggressivor"\n\
echo "=================================="\n\
\n\
Xvfb :99 -screen 0 1024x768x16 &\n\
sleep 3\n\
\n\
fluxbox &\n\
\n\
echo "Starting simple web server..."\n\
mkdir -p /web\n\
echo "MT5 Aggressivor Running" > /web/index.html\n\
cd /web\n\
python3 -m http.server 8080 &\n\
\n\
echo "Searching for MT5 terminal..."\n\
MT5=$(find /root/.wine -iname terminal64.exe | head -1)\n\
\n\
if [ -z "$MT5" ]; then\n\
  echo "MT5 NOT FOUND"\n\
  find /root/.wine | tail -50\n\
else\n\
  echo "MT5 FOUND: $MT5"\n\
fi\n\
\n\
EXPERTS=$(find /root/.wine -type d -name Experts | head -1)\n\
\n\
if [ ! -z "$EXPERTS" ]; then\n\
  cp /app/test.mq5 "$EXPERTS/test.mq5"\n\
  echo "EA copied successfully"\n\
fi\n\
\n\
echo "Launching MT5..."\n\
wine "$MT5" &\n\
\n\
echo "Container ready"\n\
\n\
tail -f /dev/null\n' > /start.sh && chmod +x /start.sh

# ============================================
# PORT
# ============================================
EXPOSE 8080

CMD ["/start.sh"]
