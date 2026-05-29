FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:99
ENV WINEPREFIX=/root/.wine
ENV WINEARCH=win64
ENV WINEDEBUG=-all

# ============================================
# INSTALL ONLY REQUIRED PACKAGES
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
    unzip && \
    rm -rf /var/lib/apt/lists/*

# ============================================
# CREATE WORKDIR
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
Xvfb :99 -screen 0 1024x768x16 &\n\
sleep 5\n\
wineboot --init\n\
sleep 10\n\
mkdir -p "/root/.wine/drive_c/MT5"\n\
cd /root/.wine/drive_c/MT5\n\
wget -O mt5setup.exe https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe\n\
wine mt5setup.exe /silent || true\n\
sleep 20\n\
find /root/.wine -type d -name Experts | head -1 | xargs -I {} cp /app/test.mq5 "{}/test.mq5"\n\
while true; do sleep 3600; done\n' > /start.sh && chmod +x /start.sh

# ============================================
# PORT
# ============================================
EXPOSE 8080

CMD ["/start.sh"]
