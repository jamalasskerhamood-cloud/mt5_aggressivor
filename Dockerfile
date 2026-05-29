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
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ============================================
# INSTALL LATEST noVNC + websockify
# ============================================
RUN git clone --depth 1 https://github.com/novnc/noVNC.git /opt/novnc && \
    git clone --depth 1 https://github.com/novnc/websockify.git /opt/novnc/utils/websockify

# ============================================
# COMPLETE FIX FOR addEventListener ERROR
# ============================================
# Method 1: Patch the ui.js file to add missing elements before initialization
RUN cat >> /opt/novnc/app/ui.js <<'EOF'

// Custom patch to fix missing DOM elements
(function() {
    var originalStart = UI.prototype.start;
    UI.prototype.start = function() {
        // Create missing elements before starting
        var missingElements = [
            'noVNC_clipboard_button',
            'noVNC_clipboard_clear_button',
            'noVNC_settings_button',
            'noVNC_connect_button'
        ];
        
        missingElements.forEach(function(id) {
            if (!document.getElementById(id)) {
                var btn = document.createElement('button');
                btn.id = id;
                btn.style.display = 'none';
                document.body.appendChild(btn);
            }
        });
        
        // Call original start function
        return originalStart.apply(this, arguments);
    };
})();
EOF

# Method 2: Create a completely new vnc.html that doesn't rely on UI.js clipboard handlers
RUN cat > /opt/novnc/vnc.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes">
    <title>MT5 VNC Client</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            background: #1a1a1a;
            overflow: hidden;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif;
        }
        #screen {
            position: absolute;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: #000;
        }
        .controls {
            position: fixed;
            bottom: 20px;
            right: 20px;
            z-index: 10000;
            background: rgba(0,0,0,0.8);
            padding: 8px 12px;
            border-radius: 8px;
            backdrop-filter: blur(10px);
            display: flex;
            gap: 8px;
        }
        button {
            background: #4CAF50;
            color: white;
            border: none;
            padding: 8px 16px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 14px;
            font-weight: 500;
            transition: all 0.2s;
        }
        button:hover {
            background: #45a049;
            transform: scale(1.02);
        }
        button:active {
            transform: scale(0.98);
        }
        .status {
            position: fixed;
            top: 20px;
            left: 20px;
            z-index: 10000;
            background: rgba(0,0,0,0.7);
            padding: 6px 12px;
            border-radius: 6px;
            color: #0f0;
            font-size: 12px;
            font-family: monospace;
            backdrop-filter: blur(5px);
            pointer-events: none;
        }
        @media (max-width: 768px) {
            .controls button {
                padding: 10px 20px;
                font-size: 16px;
            }
        }
    </style>
</head>
<body>
    <div id="screen"></div>
    <div class="status" id="status">Connecting...</div>
    <div class="controls">
        <button onclick="document.documentElement.requestFullscreen()">⛶ Fullscreen</button>
        <button onclick="window.location.reload()">⟳ Refresh</button>
        <button onclick="window.rfb?.disconnect(); setTimeout(()=>window.location.reload(), 100)">🔌 Reconnect</button>
    </div>

    <script>
        (function() {
            let rfb;
            const statusDiv = document.getElementById('status');
            
            function updateStatus(message, isError = false) {
                statusDiv.textContent = message;
                statusDiv.style.color = isError ? '#f00' : '#0f0';
                console.log('[VNC]', message);
            }
            
            function connect() {
                try {
                    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
                    const wsUrl = `${protocol}//${window.location.hostname}:8080/websockify`;
                    
                    updateStatus('Connecting to ' + wsUrl);
                    
                    // Create RFB connection directly
                    rfb = new RFB(document.getElementById('screen'), wsUrl, {
                        credentials: { password: '' },
                        shared: true,
                        view_only: false,
                        resizeSession: true
                    });
                    
                    rfb.addEventListener('connect', () => {
                        updateStatus('✓ Connected');
                    });
                    
                    rfb.addEventListener('disconnect', (e) => {
                        updateStatus('✗ Disconnected: ' + (e.detail.reason || 'Unknown'), true);
                        setTimeout(connect, 5000);
                    });
                    
                    rfb.addEventListener('securityfailure', (e) => {
                        updateStatus('Security error: ' + e.detail.reason, true);
                    });
                    
                    rfb.addEventListener('clipboard', (e) => {
                        console.log('Clipboard data received');
                    });
                    
                } catch (error) {
                    updateStatus('Error: ' + error.message, true);
                    setTimeout(connect, 5000);
                }
            }
            
            // Load RFB and connect
            if (typeof RFB === 'undefined') {
                const script = document.createElement('script');
                script.src = '/novnc/app/rfb.js';
                script.onload = () => {
                    updateStatus('RFB loaded, connecting...');
                    connect();
                };
                script.onerror = () => {
                    updateStatus('Failed to load RFB library', true);
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

# Method 3: Disable clipboard UI entirely by modifying the UI class
RUN sed -i '/addClipboardHandlers/,/}/d' /opt/novnc/app/ui.js || true && \
    sed -i 's/this.addClipboardHandlers();/\/\/ Clipboard handlers disabled for mobile compatibility/' /opt/novnc/app/ui.js || true

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
# CREATE SIMPLE VNC HTML REDIRECT
# ============================================
RUN cat > /opt/novnc/index.html <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta http-equiv="refresh" content="0; url=/vnc.html?autoconnect=1&resize=remote">
</head>
<body>
    <p>Redirecting to <a href="/vnc.html?autoconnect=1&resize=remote">VNC Client</a>...</p>
</body>
</html>
EOF

# ============================================
# ENTRYPOINT
# ============================================
RUN cat > /entrypoint.sh <<'EOF'
#!/bin/bash
set -e

echo "======================================="
echo "STARTING MT5 + noVNC (Fixed)"
echo "======================================="

rm -rf /tmp/.X*

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
xterm -geometry 120x30+20+20 &
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
# START noVNC with explicit web dir
# ========================================
cd /opt/novnc
python3 /opt/novnc/utils/websockify/websockify.py \
  --web /opt/novnc \
  8080 \
  localhost:5900 \
  --verbose &
sleep 5

# ========================================
# INIT WINE
# ========================================
wineboot --init
sleep 10

MT5_EXE="/root/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe"

# ========================================
# INSTALL MT5 IF MISSING
# ========================================
if [ ! -f "$MT5_EXE" ]; then
    echo "Installing MT5..."
    wine /root/mt5setup.exe /auto
    sleep 90
fi

# ========================================
# START MT5
# ========================================
echo "Launching MT5..."
wine "$MT5_EXE" /portable &
sleep 30

# ========================================
# FIND MT5 DATA FOLDER
# ========================================
DATA_DIR=$(find /root/.wine -type d -path "*MetaQuotes/Terminal/*/MQL5" | head -n 1)

if [ -z "$DATA_DIR" ]; then
    DATA_DIR="/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5"
fi

mkdir -p "$DATA_DIR/Experts"

# ========================================
# COPY EA
# ========================================
cp "/root/test.mq5" "$DATA_DIR/Experts/"

echo "======================================="
echo "EA INSTALLED:"
echo "$DATA_DIR/Experts/"
echo "======================================="

ls -la "$DATA_DIR/Experts/"

# ========================================
# START MT5 PYTHON BRIDGE
# ========================================
python3 -m mt5linux --host 0.0.0.0 --port 8001 &

echo "======================================="
echo "SYSTEM READY"
echo "======================================="
echo "ACCESS VNC AT: http://localhost:8080/vnc.html"
echo "======================================="

tail -f /dev/null
EOF

RUN chmod +x /entrypoint.sh && dos2unix /entrypoint.sh

EXPOSE 8080 8001

CMD ["/bin/bash", "/entrypoint.sh"]
