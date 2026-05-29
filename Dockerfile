FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:1
ENV WINEPREFIX=/root/.wine
ENV WINEARCH=win64
ENV WINEDEBUG=-all

# ==========================================
# INSTALL SYSTEM + GUI + WINE
# ==========================================
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y \
    wget \
    curl \
    unzip \
    supervisor \
    xfce4 \
    xfce4-goodies \
    xrdp \
    dbus-x11 \
    xvfb \
    net-tools \
    software-properties-common \
    cabextract \
    wine64 \
    wine32 \
    winbind \
    openjdk-11-jdk \
    tomcat9 \
    postgresql \
    postgresql-contrib \
    && rm -rf /var/lib/apt/lists/*

# ==========================================
# INSTALL GUACD
# ==========================================
RUN apt-get update && apt-get install -y \
    guacd \
    libguac-client-rdp0 \
    libguac-client-vnc0 \
    libguac-client-ssh0

# ==========================================
# DOWNLOAD GUACAMOLE WAR
# ==========================================
RUN wget https://archive.apache.org/dist/guacamole/1.5.5/binary/guacamole-1.5.5.war \
    -O /var/lib/tomcat9/webapps/guacamole.war

# ==========================================
# CREATE GUACAMOLE CONFIG
# ==========================================
RUN mkdir -p /etc/guacamole

RUN echo "guacd-hostname: localhost" > /etc/guacamole/guacamole.properties && \
    echo "guacd-port: 4822" >> /etc/guacamole/guacamole.properties

# ==========================================
# INSTALL MT5
# ==========================================
RUN mkdir -p /mt5

RUN wget https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe \
    -O /mt5/mt5setup.exe

RUN wineboot --init || true
RUN sleep 15

RUN xvfb-run wine /mt5/mt5setup.exe /silent || true
RUN sleep 25

# ==========================================
# COPY YOUR EA
# ==========================================
COPY test.mq5 /root/.wine/drive_c/Program\ Files/MetaTrader\ 5/MQL5/Experts/test.mq5

# ==========================================
# XRDP CONFIG
# ==========================================
RUN echo "xfce4-session" > /root/.xsession

RUN adduser xrdp ssl-cert

# ==========================================
# START SCRIPT
# ==========================================
RUN echo '#!/bin/bash
\
service dbus start
\
service postgresql start
\
service xrdp start
\
service tomcat9 start
\
/usr/sbin/guacd -f &
\
Xvfb :1 -screen 0 1280x720x16 &
\
export DISPLAY=:1
\
wine "/root/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe" &
\
tail -f /dev/null' > /start.sh

RUN chmod +x /start.sh

# ==========================================
# PORTS
# ==========================================
EXPOSE 8080
EXPOSE 3389
EXPOSE 4822

CMD ["/start.sh"]
