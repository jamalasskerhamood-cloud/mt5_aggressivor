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
# INSTALL noVNC + websockify - FIXED PATHS
# ============================================
RUN git clone --depth 1 https://github.com/novnc/noVNC.git /opt/novnc && \
    git clone --depth 1 https://github.com/novnc/websockify.git /opt/websockify

# Create symbolic link for websockify
RUN ln -s /opt/websockify/websockify /usr/local/bin/websockify && \
    chmod +x /usr/local/bin/websockify

# ============================================
# FIX THE addEventListener ERROR - Complete replacement
# ============================================
# Replace the problematic vnc.html with a simplified working version
RUN cat > /opt/novnc/vnc.html <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes">
    <title>MT5 Trading Platform</title>
    <style>
        body {
            margin: 0;
            padding: 0;
            overflow: hidden;
            background: #1a1a1a;
            font-family: Arial, sans-serif;
        }
        #canvas {
            position: absolute;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: #000;
        }
        .toolbar {
            position: fixed;
            bottom: 20px;
            right: 20px;
            z-index: 1000;
            background: rgba(0,0,0,0.8);
            padding: 10px;
            border-radius: 8px;
            gap: 8px;
            display: flex;
        }
        button {
            background: #2c3e50;
            color: white;
            border: none;
            padding: 8px 16px;
            border-radius: 5px;
            cursor: pointer;
            font-size: 14px;
        }
        button:hover {
            background: #3498db;
        }
        .status {
            position: fixed;
            top: 20px;
            left: 20px;
            background: rgba(0,0,0,0.7);
            color: #2ecc71;
            padding: 5px 10px;
            border-radius: 5px;
            font-size: 12px;
            font-family: monospace;
            z-index: 1000;
        }
    </style>
</head>
<body>
    <div id="canvas"></div>
    <div class="status" id="status">Initializing...</div>
    <div class="toolbar">
        <button onclick="document.documentElement.requestFullscreen()">Fullscreen</button>
        <button onclick="window.location.reload()">Refresh</button>
    </div>

    <script>
        // Simple VNC client without complex UI elements
        (function() {
            let rfb;
            const statusDiv = document.getElementById('status');
            
            function setStatus(msg, isError = false) {
                statusDiv.textContent = msg;
                statusDiv.style.color = isError ? '#e74c3c' : '#2ecc71';
                console.log('[VNC]', msg);
            }
            
            function connect() {
                try {
                    const host = window.location.hostname;
                    const port = 8080;
                    const url = `ws://${host}:${port}/websockify`;
                    
                    setStatus(`Connecting to ${host}...`);
                    
                    // Create RFB connection
                    rfb = new RFB(document.getElementById('canvas'), url, {
                        credentials: { password: '' },
                        shared: true,
                        view_only: false,
                        resizeSession: true
                    });
                    
                    rfb.addEventListener('connect', () => {
                        setStatus('Connected to MT5');
                    });
                    
                    rfb.addEventListener('disconnect', (e) => {
                        setStatus('Disconnected: ' + (e.detail.reason || 'unknown'), true);
                        setTimeout(connect, 5000);
                    });
                    
                    rfb.addEventListener('securityfailure', (e) => {
                        setStatus('Security error', true);
                    });
                    
                } catch (error) {
                    setStatus('Error: ' + error.message, true);
                    setTimeout(connect, 5000);
                }
            }
            
            // Load RFB library
            if (typeof RFB === 'undefined') {
                const script = document.createElement('script');
                script.src = '/novnc/app/rfb.js';
                script.onload = () => {
                    setStatus('Loading complete, connecting...');
                    connect();
                };
                script.onerror = () => {
                    setStatus('Failed to load VNC library', true);
                };
                document.head.appendChild(script);
            } else {
                connect();
            }
        })();
    </script>
</body>
</html>
EOF

# Create fallback index.html
RUN cat > /opt/novnc/index.html <<'EOF'
<!DOCTYPE html>
<html>
<head><meta http-equiv="refresh" content="0; url=/vnc.html"></head>
<body>Redirecting to <a href="/vnc.html">VNC Client</a>...</body>
</html>
EOF

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
# COPY EA
# ============================================
COPY test.mq5 /root/test.mq5

# ============================================
# ENTRYPOINT - FIXED websockify path
# ============================================
RUN cat > /entrypoint.sh <<'EOF'
#!/bin/bash
set -e

echo "======================================="
echo "STARTING MT5 + noVNC (Railway Fixed)"
echo "======================================="

# Clean up old X11 locks
rm -rf /tmp/.X* /tmp/.X11-unix

# Start Xvfb
Xvfb :1 -screen 0 1280x1024x24 -ac -noreset &
export DISPLAY=:1
sleep 3

# Start fluxbox (lightweight window manager)
fluxbox &
sleep 2

# Start x11vnc
x11vnc -display :1 -forever -shared -nopw -rfbport 5900 -noxdamage &
sleep 2

# Start websockify (using correct path)
websockify --web /opt/novnc 8080 localhost:5900 &
sleep 3

# Initialize Wine
wineboot --init
sleep 10

MT5_EXE="/root/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe"

# Install MT5 if not present
if [ ! -f "$MT5_EXE" ]; then
    echo "Installing MT5 (first time setup)..."
    wine /root/mt5setup.exe /auto
    sleep 90
fi

# Start MT5
echo "Launching MetaTrader 5..."
wine "$MT5_EXE" /portable &
sleep 30

# Find and copy EA
DATA_DIR=$(find /root/.wine -type d -path "*MetaQuotes/Terminal/*/MQL5" 2>/dev/null | head -n 1)
if [ -z "$DATA_DIR" ]; then
    DATA_DIR="/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5"
fi

mkdir -p "$DATA_DIR/Experts"
cp /root/test.mq5 "$DATA_DIR/Experts/" 2>/dev/null || echo "EA file not found"

echo "======================================="
echo "DEPLOYMENT SUCCESSFUL!"
echo "======================================="
echo "Access MT5 at: https://${RAILWAY_PUBLIC_DOMAIN:-localhost}/vnc.html"
echo "======================================="

# Start Python bridge
python3 -m mt5linux --host 0.0.0.0 --port 8001 &

# Keep container running
tail -f /dev/null
EOF

RUN chmod +x /entrypoint.sh && dos2unix /entrypoint.sh

EXPOSE 8080 8001

CMD ["/bin/bash", "/entrypoint.sh"]
