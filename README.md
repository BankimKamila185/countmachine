# 🔍 Product Count Scanner App (AI Computer Vision + Flutter)

A real-time Computer Vision counter for scanning products (such as jewelry pins, components, or hardware parts) using a live camera feed. It automatically counts the pieces on the spot, draws bounding boxes, and announces the count aloud via Text-to-Speech (TTS).

---

## 🌟 Key Features

- **Real-Time Live Camera Scanner**: 15–30 FPS live frame counting with immediate bounding boxes and pinpoint center dots.
- **On-the-Spot Voice & Visual Announcements**: High-visibility neon HUD counter and text-to-speech speaker (*"14 pieces detected"*).
- **Dual Detection Engines**:
  - **Jewelry Pin & Gemstone Mode**: Special HSV color segmentation and morphological separation for blue gemstone heads and needle tails.
  - **Generic Contrast Mode**: Adaptive threshold contour detector for any scattered parts or hardware items.
- **Sensitivity & Torch Controls**: On-the-fly threshold tuning and flashlight toggle for low-light environments.
- **Photo Audit Mode**: Static image upload and audit from gallery or snapshot.
- **Built-in Web Scanner**: Interactive browser dashboard available directly from the Python backend for instant testing with your webcam.

---

## 📂 Project Structure

```
proudct count app/
├── backend/                      # Python AI & Computer Vision Backend
│   ├── app.py                    # FastAPI + WebSocket server + Live Web Dashboard
│   ├── pin_counter.py            # HSV segmentation & contour detection algorithms
│   ├── test_counting.py          # Standalone OpenCV webcam testing tool
│   └── requirements.txt          # Python dependencies
│
└── frontend/                     # Flutter App (Mobile & Desktop)
    ├── lib/
    │   ├── main.dart             # App entry point
    │   ├── models/
    │   │   └── detected_item.dart# Data models for detected objects
    │   ├── screens/
    │   │   ├── live_scanner_screen.dart # Live camera scanner screen
    │   │   └── image_audit_screen.dart  # Static photo audit screen
    │   ├── services/
    │   │   ├── count_api_service.dart   # WebSocket & REST API communication
    │   │   └── tts_service.dart         # Voice announcement service
    │   └── widgets/
    │       └── bounding_box_overlay.dart# CustomPainter for neon bounding boxes
    └── pubspec.yaml
```

---

## 🚀 How to Run

### Step 1: Start the Python Backend Server
```bash
cd "/Users/bankimkamila/proudct count app/backend"
source venv/bin/activate
uvicorn app:app --host 0.0.0.0 --port 8000
```
- Open **`http://localhost:8000`** in your browser for the **Live Web Camera Scanner**.

---

### Step 2: Run Standalone OpenCV Test (Optional)
To test directly in a native OpenCV window with your webcam:
```bash
cd "/Users/bankimkamila/proudct count app/backend"
source venv/bin/activate
python test_counting.py
```
*(Press `+`/`-` to adjust sensitivity in real time, `q` to quit)*

---

### Step 3: Run the Flutter App
```bash
cd "/Users/bankimkamila/proudct count app/frontend"
flutter run
```
- For running on a physical Android/iOS phone connected to the same Wi-Fi, open **Settings** (⚙️) inside the app and set the Server Address to your laptop's local IP (e.g. `192.168.1.X:8000`).
