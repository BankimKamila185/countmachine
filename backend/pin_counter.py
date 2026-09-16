import cv2
import numpy as np
from typing import List, Dict, Tuple, Any

class PinCounter:
    def __init__(self):
        # Default HSV ranges for detecting the distinct blue gemstone head
        # Hue: 95 - 135 (Blue in OpenCV 0-180 scale)
        # Saturation: 50 - 255
        # Value: 40 - 255
        self.blue_lower = np.array([95, 50, 40], dtype=np.uint8)
        self.blue_upper = np.array([135, 255, 255], dtype=np.uint8)
        
        # Minimum & maximum contour area for valid pieces
        self.min_gem_area = 50
        self.max_gem_area = 50000

    def update_hsv_thresholds(self, h_low: int, h_high: int, s_low: int, s_high: int, v_low: int, v_high: int):
        self.blue_lower = np.array([h_low, s_low, v_low], dtype=np.uint8)
        self.blue_upper = np.array([h_high, s_high, v_high], dtype=np.uint8)

    def process_frame(
        self, 
        image_bgr: np.ndarray, 
        sensitivity: float = 0.5, 
        mode: str = "jewelry_pin"
    ) -> Dict[str, Any]:
        """
        Process a single image/frame to count and locate products.
        Returns:
            {
                "count": int,
                "items": [
                    {
                        "id": int,
                        "center": [x, y],
                        "bbox": [x, y, w, h],
                        "contour": [[x,y], ...],
                        "confidence": float,
                        "type": str
                    }
                ],
                "processed_width": int,
                "processed_height": int
            }
        """
        h, w = image_bgr.shape[:2]
        
        # 1. Convert to HSV for robust color separation
        hsv = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2HSV)
        
        # 2. Smooth with Gaussian blur to reduce noise
        blurred = cv2.GaussianBlur(hsv, (5, 5), 0)
        
        # 3. Create Color Mask for Blue Gemstones
        mask = cv2.inRange(blurred, self.blue_lower, self.blue_upper)
        
        # 4. Morphological Opening to remove salt-and-pepper noise, then Closing/Dilating
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel, iterations=2)
        mask = cv2.morphologyEx(mask, cv2.MORPH_DILATE, kernel, iterations=1)
        
        # 5. Connected Component Analysis
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        detected_items = []
        item_id = 1
        
        for cnt in contours:
            area = cv2.contourArea(cnt)
            if area < self.min_gem_area * (1.2 - sensitivity):
                continue
            if area > self.max_gem_area:
                continue
                
            x, y, bw, bh = cv2.boundingRect(cnt)
            
            # Compute center of mass
            M = cv2.moments(cnt)
            if M["m00"] != 0:
                cx = int(M["m10"] / M["m00"])
                cy = int(M["m01"] / M["m00"])
            else:
                cx, cy = x + bw // 2, y + bh // 2
                
            # Expand bounding box slightly to cover the pin needle if attached
            pad_x = int(bw * 0.3)
            pad_y = int(bh * 0.3)
            
            exp_x = max(0, x - pad_x)
            exp_y = max(0, y - pad_y)
            exp_w = min(w - exp_x, bw + pad_x * 2)
            exp_h = min(h - exp_y, bh + pad_y * 2)
            
            # Simplify contour points for lightweight JSON transport
            epsilon = 0.02 * cv2.arcLength(cnt, True)
            approx = cv2.approxPolyDP(cnt, epsilon, True)
            contour_pts = approx.reshape(-1, 2).tolist()
            
            detected_items.append({
                "id": item_id,
                "center": [cx, cy],
                "bbox": [exp_x, exp_y, exp_w, exp_h],
                "gem_bbox": [x, y, bw, bh],
                "contour": contour_pts,
                "area": float(area),
                "confidence": min(0.99, 0.70 + (area / (self.min_gem_area * 10)) * 0.25),
                "type": "jewelry_pin"
            })
            item_id += 1
            
        # Also perform adaptive edge/contour check if no blue gems detected (generic mode fallback)
        if len(detected_items) == 0 and mode == "generic":
            gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
            adaptive_thresh = cv2.adaptiveThreshold(
                gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY_INV, 21, 5
            )
            g_contours, _ = cv2.findContours(adaptive_thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            for g_cnt in g_contours:
                g_area = cv2.contourArea(g_cnt)
                if 100 < g_area < 50000:
                    gx, gy, gbw, gbh = cv2.boundingRect(g_cnt)
                    detected_items.append({
                        "id": item_id,
                        "center": [gx + gbw // 2, gy + gbh // 2],
                        "bbox": [gx, gy, gbw, gbh],
                        "gem_bbox": [gx, gy, gbw, gbh],
                        "contour": [],
                        "area": float(g_area),
                        "confidence": 0.75,
                        "type": "generic_piece"
                    })
                    item_id += 1

        return {
            "count": len(detected_items),
            "items": detected_items,
            "processed_width": w,
            "processed_height": h
        }

    def draw_annotations(self, image_bgr: np.ndarray, results: Dict[str, Any]) -> np.ndarray:
        """Draw bounding boxes, center dots, ID numbers, and HUD counter."""
        annotated = image_bgr.copy()
        for item in results.get("items", []):
            x, y, w, h = item["bbox"]
            cx, cy = item["center"]
            item_id = item["id"]
            
            # Draw Neon Cyan / Emerald Green Bounding Box
            cv2.rectangle(annotated, (x, y), (x + w, y + h), (0, 255, 128), 2)
            
            # Draw glowing center dot
            cv2.circle(annotated, (cx, cy), 6, (0, 0, 255), -1)
            cv2.circle(annotated, (cx, cy), 8, (255, 255, 255), 2)
            
            # Draw Badge Label
            label = f"#{item_id}"
            (tw, th), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 2)
            cv2.rectangle(annotated, (x, y - 20), (x + tw + 6, y), (0, 255, 128), -1)
            cv2.putText(annotated, label, (x + 3, y - 5), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 0), 2)
            
        # Draw HUD Total Count Header
        count_text = f"TOTAL PIECES: {results.get('count', 0)}"
        cv2.rectangle(annotated, (20, 20), (320, 75), (0, 0, 0), -1)
        cv2.rectangle(annotated, (20, 20), (320, 75), (0, 255, 255), 2)
        cv2.putText(annotated, count_text, (35, 58), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 255, 255), 3)
        
        return annotated
