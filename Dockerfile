FROM python:3.11-slim-bookworm

USER root
ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:1
ENV WINEPREFIX=/root/.wine
ENV WINEARCH=win64
ENV WINEDEBUG=-all

RUN dpkg --add-architecture i386 && apt-get update && apt-get install -y --no-install-recommends \
    wine wine64 wine32:i386 winbind xvfb fluxbox x11vnc novnc websockify \
    wget curl procps cabextract unzip dos2unix xdotool \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir mt5linux rpyc
RUN wget -q https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe -O /root/mt5setup.exe

# Copy only the .ex5 files visible in the two screenshots
COPY EA_PapuaQ_Plus_v3.0.ex5 /root/
COPY SMC.ex5 /root/
COPY smart.ex5 /root/
COPY MA_BreakOut_Expert_Advisor.ex5 /root/
COPY AI_BREAKOUT_EA.ex5 /root/
COPY AI_trader.ex5 /root/
COPY All_in_one_Scalper_2.0.ex5 /root/
COPY Amber_waves.ex5 /root/
COPY Black_Wolf_EA_fix.ex5 /root/
COPY Boom_Crash_Terror_Scalp_EA-1.ex5 /root/
COPY Boom_1000_index_M1_32995495.ex5 /root/
COPY Boom_1000_index_M1_92583415.ex5 /root/
COPY CRASH_500_POWER_SCALPER.ex5 /root/
COPY CRASH_500_SCALPER.ex5 /root/
COPY Chefs-Gold-EA-MT5-v2.ex5 /root/
COPY Covid_24_Boom_And_Crash_Pro.ex5 /root/
COPY Crash_RVI_SMA_Scalper_EA.ex5 /root/

# ============================================
# 3. INSTALLATION & ENTRYPOINT
# ============================================
RUN cat > /entrypoint.sh << 'EOF'
#!/bin/bash
set -e
rm -rf /tmp/.X*
Xvfb :1 -screen 0 1280x1024x24 -ac &
sleep 2
fluxbox &
x11vnc -display :1 -forever -shared -nopw -rfbport 5900 &
websockify --web=/usr/share/novnc 8080 0.0.0.0:5900 &
wineboot --init
sleep 5
MT5_EXE="/root/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe"
[ ! -f "$MT5_EXE" ] && wine /root/mt5setup.exe /auto && sleep 90
wine "$MT5_EXE" &
sleep 30

DATA_DIR=$(find /root/.wine -type d -path "*MetaQuotes/Terminal/*/MQL5" | head -n 1)
[ -z "$DATA_DIR" ] && DATA_DIR="/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5"
mkdir -p "$DATA_DIR/Experts"

cp /root/EA_PapuaQ_Plus_v3.0.ex5 "$DATA_DIR/Experts/"
cp /root/SMC.ex5 "$DATA_DIR/Experts/"
cp /root/smart.ex5 "$DATA_DIR/Experts/"
cp /root/MA_BreakOut_Expert_Advisor.ex5 "$DATA_DIR/Experts/"
cp /root/AI_BREAKOUT_EA.ex5 "$DATA_DIR/Experts/"
cp /root/AI_trader.ex5 "$DATA_DIR/Experts/"
cp /root/All_in_one_Scalper_2.0.ex5 "$DATA_DIR/Experts/"
cp /root/Amber_waves.ex5 "$DATA_DIR/Experts/"
cp /root/Black_Wolf_EA_fix.ex5 "$DATA_DIR/Experts/"
cp /root/Boom_Crash_Terror_Scalp_EA-1.ex5 "$DATA_DIR/Experts/"
cp /root/Boom_1000_index_M1_32995495.ex5 "$DATA_DIR/Experts/"
cp /root/Boom_1000_index_M1_92583415.ex5 "$DATA_DIR/Experts/"
cp /root/CRASH_500_POWER_SCALPER.ex5 "$DATA_DIR/Experts/"
cp /root/CRASH_500_SCALPER.ex5 "$DATA_DIR/Experts/"
cp /root/Chefs-Gold-EA-MT5-v2.ex5 "$DATA_DIR/Experts/"
cp /root/Covid_24_Boom_And_Crash_Pro.ex5 "$DATA_DIR/Experts/"
cp /root/Crash_RVI_SMA_Scalper_EA.ex5 "$DATA_DIR/Experts/"

python3 -m mt5linux --host 0.0.0.0 --port 8001 &
tail -f /dev/null
EOF

RUN chmod +x /entrypoint.sh && dos2unix /entrypoint.sh
EXPOSE 8080 8001
CMD ["/bin/bash", "/entrypoint.sh"]
