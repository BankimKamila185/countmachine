import io
import time
import base64
import cv2
import numpy as np
from fastapi import FastAPI, UploadFile, File, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse
from pin_counter import PinCounter

app = FastAPI(title="Product Count Scanner API", version="1.0.0")

# Enable CORS for Flutter web / mobile clients
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

counter = PinCounter()

@app.get("/")
async def get_dashboard():
    """Interactive Live Web Scanner Dashboard for quick browser testing."""
    html_content = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Product Count Scanner AI</title>
        <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;600;800&display=swap" rel="stylesheet">
        <style>
            * { box-sizing: border-box; margin: 0; padding: 0; font-family: 'Plus Jakarta Sans', sans-serif; }
            body { background: #0b0f19; color: #f8fafc; min-height: 100vh; display: flex; flex-direction: column; align-items: center; padding: 24px; }
            .header { display: flex; align-items: center; justify-content: space-between; width: 100%; max-width: 1000px; margin-bottom: 20px; }
            .badge { background: linear-gradient(135deg, #3b82f6, #06b6d4); padding: 6px 14px; border-radius: 9999px; font-weight: 600; font-size: 13px; letter-spacing: 0.5px; }
            .container { display: grid; grid-template-columns: 1fr 340px; gap: 24px; width: 100%; max-width: 1000px; }
            @media (max-width: 800px) { .container { grid-template-columns: 1fr; } }
            .video-card { background: #151c2c; border: 1px solid #1e293b; border-radius: 20px; padding: 16px; position: relative; overflow: hidden; box-shadow: 0 20px 40px rgba(0,0,0,0.5); }
            .video-wrapper { position: relative; width: 100%; height: 480px; border-radius: 14px; overflow: hidden; background: #000; display: flex; align-items: center; justify-content: center; }
            video, canvas { position: absolute; top: 0; left: 0; width: 100%; height: 100%; object-fit: cover; }
            .stats-card { background: #151c2c; border: 1px solid #1e293b; border-radius: 20px; padding: 24px; display: flex; flex-direction: column; gap: 20px; box-shadow: 0 20px 40px rgba(0,0,0,0.5); }
            .count-display { background: linear-gradient(135deg, rgba(59,130,246,0.1), rgba(6,182,212,0.1)); border: 2px solid #06b6d4; border-radius: 16px; padding: 20px; text-align: center; }
            .count-number { font-size: 56px; font-weight: 800; color: #38bdf8; text-shadow: 0 0 20px rgba(56,189,248,0.5); line-height: 1; }
            .count-label { font-size: 14px; font-weight: 600; color: #94a3b8; text-transform: uppercase; margin-top: 6px; letter-spacing: 1px; }
            .btn { background: linear-gradient(135deg, #0ea5e9, #2563eb); color: white; border: none; padding: 14px 20px; border-radius: 12px; font-weight: 700; font-size: 15px; cursor: pointer; transition: all 0.2s; display: flex; align-items: center; justify-content: center; gap: 8px; width: 100%; }
            .btn:hover { transform: translateY(-2px); box-shadow: 0 8px 20px rgba(14,165,233,0.4); }
            .btn.voice-on { background: linear-gradient(135deg, #10b981, #059669); }
            .slider-group { display: flex; flex-direction: column; gap: 8px; }
            .slider-label { font-size: 13px; font-weight: 600; color: #94a3b8; display: flex; justify-content: space-between; }
            input[type="range"] { accent-color: #06b6d4; width: 100%; cursor: pointer; }
            .item-list { max-height: 140px; overflow-y: auto; background: #0f172a; border-radius: 10px; padding: 10px; font-size: 13px; }
            .item-row { display: flex; justify-content: space-between; padding: 6px 8px; border-bottom: 1px solid #1e293b; }
        </style>
    </head>
    <body>
        <div class="header">
            <div>
                <h1 style="font-size: 24px; font-weight: 800;">Product Count Scanner</h1>
                <p style="color: #64748b; font-size: 14px;">Real-Time AI Computer Vision Pin & Part Counter</p>
            </div>
            <div class="badge" id="statusBadge">LIVE ENGINE READY</div>
        </div>

        <div class="container">
            <div class="video-card">
                <div class="video-wrapper">
                    <video id="video" autoplay playsinline muted></video>
                    <canvas id="overlayCanvas"></canvas>
                </div>
            </div>

            <div class="stats-card">
                <div class="count-display">
                    <div class="count-number" id="countNum">0</div>
                    <div class="count-label">Total Pieces Detected</div>
                </div>

                <button class="btn" id="voiceBtn" onclick="toggleVoice()">
                    <span id="voiceIcon">🔊</span> <span id="voiceText">Voice Count: ON</span>
                </button>

                <div class="slider-group">
                    <div class="slider-label">
                        <span>Detection Sensitivity</span>
                        <span id="sensVal">50%</span>
                    </div>
                    <input type="range" id="sensSlider" min="10" max="100" value="50" oninput="updateSens(this.value)">
                </div>

                <div class="slider-group">
                    <div class="slider-label">
                        <span>Mode</span>
                    </div>
                    <select id="modeSelect" style="background:#0f172a; color:#f8fafc; border:1px solid #334155; padding:8px 12px; border-radius:8px; width:100%;">
                        <option value="jewelry_pin">Jewelry Blue Gem Pin</option>
                        <option value="generic">Generic Contrast Parts</option>
                    </select>
                </div>

                <div>
                    <div style="font-size: 13px; font-weight: 600; color: #94a3b8; margin-bottom: 6px;">Detected Items Log</div>
                    <div class="item-list" id="itemList">
                        <div style="color: #64748b; text-align: center; padding: 10px;">Waiting for camera feed...</div>
                    </div>
                </div>
            </div>
        </div>

        <script>
            const video = document.getElementById('video');
            const canvas = document.getElementById('overlayCanvas');
            const ctx = canvas.getContext('2d');
            const countNum = document.getElementById('countNum');
            const itemList = document.getElementById('itemList');
            let voiceEnabled = true;
            let lastSpokenCount = -1;
            let lastSpokenTime = 0;
            let currentSensitivity = 0.5;

            // Start webcam
            navigator.mediaDevices.getUserMedia({ video: { width: { ideal: 1280 }, height: { ideal: 720 } } })
                .then(stream => {
                    video.srcObject = stream;
                    video.onloadedmetadata = () => {
                        canvas.width = video.videoWidth;
                        canvas.height = video.videoHeight;
                        startProcessingLoop();
                    };
                })
                .catch(err => {
                    console.error("Camera access error:", err);
                    alert("Could not access camera. Please allow camera permissions or upload an image.");
                });

            function updateSens(val) {
                currentSensitivity = val / 100;
                document.getElementById('sensVal').innerText = val + '%';
            }

            function toggleVoice() {
                voiceEnabled = !voiceEnabled;
                document.getElementById('voiceText').innerText = voiceEnabled ? "Voice Count: ON" : "Voice Count: OFF";
                document.getElementById('voiceBtn').classList.toggle('voice-on', voiceEnabled);
            }

            function speakCount(count) {
                if (!voiceEnabled || !('speechSynthesis' in window)) return;
                const now = Date.now();
                if (count !== lastSpokenCount && (now - lastSpokenTime > 1800)) {
                    lastSpokenCount = count;
                    lastSpokenTime = now;
                    const utterance = new SpeechSynthesisUtterance(count === 1 ? '1 piece detected' : `${count} pieces detected`);
                    utterance.rate = 1.0;
                    utterance.pitch = 1.0;
                    window.speechSynthesis.cancel();
                    window.speechSynthesis.speak(utterance);
                }
            }

            // Temp offscreen canvas to capture frame
            const captureCanvas = document.createElement('canvas');
            const captureCtx = captureCanvas.getContext('2d');

            async function processFrame() {
                if (video.readyState !== video.HAVE_ENOUGH_DATA) return;
                
                captureCanvas.width = video.videoWidth || 640;
                captureCanvas.height = video.videoHeight || 480;
                captureCtx.drawImage(video, 0, 0, captureCanvas.width, captureCanvas.height);
                
                const dataUrl = captureCanvas.toDataURL('image/jpeg', 0.7);
                const base64Data = dataUrl.split(',')[1];
                const mode = document.getElementById('modeSelect').value;

                try {
                    const response = await fetch('/api/count_base64', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ image: base64Data, sensitivity: currentSensitivity, mode: mode })
                    });
                    const res = await response.json();
                    renderOverlay(res);
                } catch (e) {
                    console.error("Processing error:", e);
                }
            }

            function renderOverlay(res) {
                ctx.clearRect(0, 0, canvas.width, canvas.height);
                const count = res.count || 0;
                countNum.innerText = count;
                speakCount(count);

                let listHtml = '';
                (res.items || []).forEach(item => {
                    const [x, y, w, h] = item.bbox;
                    const [cx, cy] = item.center;

                    // Neon Green Bounding Box
                    ctx.strokeStyle = '#00ff88';
                    ctx.lineWidth = 3;
                    ctx.strokeRect(x, y, w, h);

                    // Center marker
                    ctx.fillStyle = '#ff0055';
                    ctx.beginPath();
                    ctx.arc(cx, cy, 6, 0, 2 * Math.PI);
                    ctx.fill();

                    // Pin Badge
                    ctx.fillStyle = '#00ff88';
                    ctx.fillRect(x, y - 24, 42, 22);
                    ctx.fillStyle = '#000000';
                    ctx.font = 'bold 13px sans-serif';
                    ctx.fillText(`#${item.id}`, x + 6, y - 8);

                    listHtml += `<div class="item-row"><span>Piece #${item.id}</span><span style="color:#00ff88;">X:${cx}, Y:${cy}</span></div>`;
                });

                if (res.items && res.items.length > 0) {
                    itemList.innerHTML = listHtml;
                } else {
                    itemList.innerHTML = '<div style="color: #64748b; text-align: center; padding: 10px;">No items in frame</div>';
                }
            }

            function startProcessingLoop() {
                setInterval(processFrame, 100); // 10 FPS real-time processing
            }
        </script>
    </body>
    </html>
    """
    return HTMLResponse(content=html_content)

@app.post("/api/count")
async def count_uploaded_image(
    file: UploadFile = File(...), 
    sensitivity: float = 0.5,
    mode: str = "jewelry_pin"
):
    """Count products from an uploaded image file."""
    contents = await file.read()
    nparr = np.frombuffer(contents, np.uint8)
    image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    
    if image is None:
        return JSONResponse(status_code=400, content={"error": "Invalid image file"})
        
    results = counter.process_frame(image, sensitivity=sensitivity, mode=mode)
    return JSONResponse(content=results)

@app.post("/api/count_base64")
async def count_base64_frame(payload: dict):
    """Process a base64 encoded frame from Flutter or Web client."""
    img_data = base64.b64decode(payload.get("image", ""))
    nparr = np.frombuffer(img_data, np.uint8)
    image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    
    if image is None:
        return JSONResponse(status_code=400, content={"error": "Invalid image payload"})
        
    sensitivity = payload.get("sensitivity", 0.5)
    mode = payload.get("mode", "jewelry_pin")
    results = counter.process_frame(image, sensitivity=sensitivity, mode=mode)
    return JSONResponse(content=results)

@app.websocket("/ws/count")
async def websocket_count_stream(websocket: WebSocket):
    """Real-time ultra-low latency WebSocket stream for Flutter camera frames."""
    await websocket.accept()
    try:
        while True:
            data = await websocket.receive_text()
            # Parse payload
            # Expecting base64 jpeg or JSON {"image": "base64", "sensitivity": 0.5}
            if data.startswith("{"):
                import json
                parsed = json.loads(data)
                raw_b64 = parsed.get("image", "")
                sensitivity = parsed.get("sensitivity", 0.5)
                mode = parsed.get("mode", "jewelry_pin")
            else:
                raw_b64 = data
                sensitivity = 0.5
                mode = "jewelry_pin"
                
            img_bytes = base64.b64decode(raw_b64)
            nparr = np.frombuffer(img_bytes, np.uint8)
            image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            
            if image is not None:
                start_t = time.time()
                results = counter.process_frame(image, sensitivity=sensitivity, mode=mode)
                results["latency_ms"] = round((time.time() - start_t) * 1000, 1)
                await websocket.send_json(results)
            else:
                await websocket.send_json({"count": 0, "items": [], "error": "Invalid frame"})
    except WebSocketDisconnect:
        pass
    except Exception as e:
        print(f"WebSocket error: {e}")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
