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

# Copy all unique local repository binaries into the build context
COPY SMC.ex5 /root/SMC.ex5
COPY smart.ex5 /root/smart.ex5
COPY "EA PapuaQ Plus v3.0.ex5" /root/
COPY "Boom#1000#Index M1 92583415.ex5" /root/
COPY "Boom#1000#Index M1 32995495.ex5" /root/
COPY "RedDragon_v.1.03.ex5" /root/
COPY "Galileo FX_MT5.ex5" /root/
COPY "Volatility 50 Micro EA.ex5" /root/
COPY "Vulture Dot.ex5" /root/
COPY "Vulture S-K.ex5" /root/
COPY "Boom Crash Terror Scalp EA-1.ex5" /root/
COPY "Crash RVI SMA Scalper EA.ex5" /root/
COPY "Mr P Fx - Crash and Boom Auto Scalper.ex5" /root/
COPY "CRASH 500 SCALPER.ex5" /root/
COPY "CRASH 500 POWER SCALPER.ex5" /root/
COPY "JS MA SAR Trades.ex5" /root/
COPY "NQ100m M5 79954141.ex5" /root/
COPY "Mr P Fx BC Villain 88 Robot (CRASH).ex5" /root/
COPY "AI_trader.ex5" /root/
COPY "The Spike Charger.ex5" /root/
COPY "Chef's-Gold-EA-MT5-v2.ex5" /root/
COPY "TakePropips Golden Expert MT5.ex5" /root/
COPY "Multi_Trades BC Robot.ex5" /root/
COPY "Amber waves.ex5" /root/
COPY "Pumbling_fix.ex5" /root/
COPY "AI BREAKOUT EA.ex5" /root/
COPY "Hedge Zone EURUSD_fix.ex5" /root/
COPY "FX CHOPPERS  EA.ex5" /root/
COPY "GODZILLA 2.0 SCALPER(EXTREME).ex5" /root/
COPY "GOLD POWER SCALPER 2.ex5" /root/
COPY "Nasdaq (matrix) 2_0.ex5" /root/
COPY "Sun v1.5_fix.ex5" /root/
COPY "Sun v1.9-DLL-3C10674F.ex5" /root/
COPY "Correlation 2024 v.24.1.ex4" /root/
COPY "Covid 24 Boom And Crash Pro.ex5" /root/
COPY "All in one Scalper 2.0.ex5" /root/
COPY "HANDS OF GOD V3.0 EA.ex5" /root/
COPY "Thomas_mt5.ex5" /root/
COPY "!! MA_BreakOut Expert Advisor!!.ex5" /root/
COPY "Black Wolf EA_fix.ex5" /root/
COPY "STEP-IN. GUN.ex5" /root/
COPY "SNIPER GOLD X_by @gediyafx.ex5" /root/
COPY "smart risk ea_by @gediyafx.ex5" /root/
COPY "Dark Algo V1.5_nodll_1420.ex4" /root/
COPY "Elise FX_fix_1420.ex4" /root/
COPY "EA_Golden_Moon_V7_fix_1420.ex4" /root/
COPY "Elite Forex Scalper v6.20_fix_1420.ex4" /root/
COPY "Golden Shine MT4_fix_1420.ex4" /root/
COPY "Happy News v1.5_fix_1420.ex4" /root/
COPY "PRIME SCALPER GOLD- 1420.ex4" /root/
COPY "White Hat FX V2.0_fix1420.ex4" /root/

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

cp /root/SMC.ex5 "$DATA_DIR/Experts/SMC.ex5"
cp /root/smart.ex5 "$DATA_DIR/Experts/smart.ex5"
cp "/root/EA PapuaQ Plus v3.0.ex5" "$DATA_DIR/Experts/"
cp "/root/Boom#1000#Index M1 92583415.ex5" "$DATA_DIR/Experts/"
cp "/root/Boom#1000#Index M1 32995495.ex5" "$DATA_DIR/Experts/"
cp "/root/RedDragon_v.1.03.ex5" "$DATA_DIR/Experts/"
cp "/root/Galileo FX_MT5.ex5" "$DATA_DIR/Experts/"
cp "/root/Volatility 50 Micro EA.ex5" "$DATA_DIR/Experts/"
cp "/root/Vulture Dot.ex5" "$DATA_DIR/Experts/"
cp "/root/Vulture S-K.ex5" "$DATA_DIR/Experts/"
cp "/root/Boom Crash Terror Scalp EA-1.ex5" "$DATA_DIR/Experts/"
cp "/root/Crash RVI SMA Scalper EA.ex5" "$DATA_DIR/Experts/"
cp "/root/Mr P Fx - Crash and Boom Auto Scalper.ex5" "$DATA_DIR/Experts/"
cp "/root/CRASH 500 SCALPER.ex5" "$DATA_DIR/Experts/"
cp "/root/CRASH 500 POWER SCALPER.ex5" "$DATA_DIR/Experts/"
cp "/root/JS MA SAR Trades.ex5" "$DATA_DIR/Experts/"
cp "/root/NQ100m M5 79954141.ex5" "$DATA_DIR/Experts/"
cp "/root/Mr P Fx BC Villain 88 Robot (CRASH).ex5" "$DATA_DIR/Experts/"
cp "/root/AI_trader.ex5" "$DATA_DIR/Experts/"
cp "/root/The Spike Charger.ex5" "$DATA_DIR/Experts/"
cp "/root/Chef's-Gold-EA-MT5-v2.ex5" "$DATA_DIR/Experts/"
cp "/root/TakePropips Golden Expert MT5.ex5" "$DATA_DIR/Experts/"
cp "/root/Multi_Trades BC Robot.ex5" "$DATA_DIR/Experts/"
cp "/root/Amber waves.ex5" "$DATA_DIR/Experts/"
cp "/root/Pumbling_fix.ex5" "$DATA_DIR/Experts/"
cp "/root/AI BREAKOUT EA.ex5" "$DATA_DIR/Experts/"
cp "/root/Hedge Zone EURUSD_fix.ex5" "$DATA_DIR/Experts/"
cp "/root/FX CHOPPERS  EA.ex5" "$DATA_DIR/Experts/"
cp "/root/GODZILLA 2.0 SCALPER(EXTREME).ex5" "$DATA_DIR/Experts/"
cp "/root/GOLD POWER SCALPER 2.ex5" "$DATA_DIR/Experts/"
cp "/root/Nasdaq (matrix) 2_0.ex5" "$DATA_DIR/Experts/"
cp "/root/Sun v1.5_fix.ex5" "$DATA_DIR/Experts/"
cp "/root/Sun v1.9-DLL-3C10674F.ex5" "$DATA_DIR/Experts/"
cp "/root/Correlation 2024 v.24.1.ex4" "$DATA_DIR/Experts/"
cp "/root/Covid 24 Boom And Crash Pro.ex5" "$DATA_DIR/Experts/"
cp "/root/All in one Scalper 2.0.ex5" "$DATA_DIR/Experts/"
cp "/root/HANDS OF GOD V3.0 EA.ex5" "$DATA_DIR/Experts/"
cp "/root/Thomas_mt5.ex5" "$DATA_DIR/Experts/"
cp "/root/!! MA_BreakOut Expert Advisor!!.ex5" "$DATA_DIR/Experts/"
cp "/root/Black Wolf EA_fix.ex5" "$DATA_DIR/Experts/"
cp "/root/STEP-IN. GUN.ex5" "$DATA_DIR/Experts/"
cp "/root/SNIPER GOLD X_by @gediyafx.ex5" "$DATA_DIR/Experts/"
cp "/root/smart risk ea_by @gediyafx.ex5" "$DATA_DIR/Experts/"
cp "/root/Dark Algo V1.5_nodll_1420.ex4" "$DATA_DIR/Experts/"
cp "/root/Elise FX_fix_1420.ex4" "$DATA_DIR/Experts/"
cp "/root/EA_Golden_Moon_V7_fix_1420.ex4" "$DATA_DIR/Experts/"
cp "/root/Elite Forex Scalper v6.20_fix_1420.ex4" "$DATA_DIR/Experts/"
cp "/root/Golden Shine MT4_fix_1420.ex4" "$DATA_DIR/Experts/"
cp "/root/Happy News v1.5_fix_1420.ex4" "$DATA_DIR/Experts/"
cp "/root/PRIME SCALPER GOLD- 1420.ex4" "$DATA_DIR/Experts/"
cp "/root/White Hat FX V2.0_fix1420.ex4" "$DATA_DIR/Experts/"

python3 -m mt5linux --host 0.0.0.0 --port 8001 &
tail -f /dev/null
EOF

RUN chmod +x /entrypoint.sh && dos2unix /entrypoint.sh
EXPOSE 8080 8001
CMD ["/bin/bash", "/entrypoint.sh"]
