import cv2
import numpy as np
from typing import List, Dict, Tuple, Any

class PinCounter:
    def __init__(self):
        # HSV ranges for Blue Gemstone Head
        self.blue_lower = np.array([85, 40, 25], dtype=np.uint8)
        self.blue_upper = np.array([145, 255, 255], dtype=np.uint8)
        
        self.min_gem_area = 80
        self.max_gem_area = 100000

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
        Process a single image/frame to count and locate products with high accuracy.
        Handles both front-facing blue gemstone and back-facing dark metallic pin settings.
        """
        h, w = image_bgr.shape[:2]
        hsv = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2HSV)
        gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
        
        detected_items = []
        item_id = 1
        
        # 1. Primary: Blue Gemstone Detection (Front-facing)
        if mode in ["jewelry_pin", "auto"]:
            blue_mask = cv2.inRange(hsv, self.blue_lower, self.blue_upper)
            k_open = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
            blue_clean = cv2.morphologyEx(blue_mask, cv2.MORPH_OPEN, k_open, iterations=1)
            blue_dilated = cv2.dilate(blue_clean, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7)), iterations=2)
            
            cnts, _ = cv2.findContours(blue_dilated, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            min_area = self.min_gem_area * (1.3 - sensitivity)
            
            for c in cnts:
                area = cv2.contourArea(c)
                if min_area < area < (w * h * 0.35):
                    x, y, bw, bh = cv2.boundingRect(c)
                    M = cv2.moments(c)
                    cx = int(M["m10"] / M["m00"]) if M["m00"] > 0 else x + bw // 2
                    cy = int(M["m01"] / M["m00"]) if M["m00"] > 0 else y + bh // 2
                    
                    # Expand bounding box to encompass the long pin needle
                    exp_x = max(0, x - int(bw * 1.5))
                    exp_y = max(0, y - int(bh * 0.5))
                    exp_w = min(w - exp_x, bw + int(bw * 3.0))
                    exp_h = min(h - exp_y, bh + int(bh * 1.0))
                    
                    # Simplify contour
                    epsilon = 0.02 * cv2.arcLength(c, True)
                    approx = cv2.approxPolyDP(c, epsilon, True)
                    contour_pts = approx.reshape(-1, 2).tolist()
                    
                    detected_items.append({
                        "id": item_id,
                        "center": [cx, cy],
                        "gem_bbox": [x, y, bw, bh],
                        "bbox": [exp_x, exp_y, exp_w, exp_h],
                        "contour": contour_pts,
                        "area": float(area),
                        "confidence": 0.99,
                        "type": "blue_gemstone_pin"
                    })
                    item_id += 1
                    
        # 2. Secondary: Adaptive Contrast Detection (Back-facing metallic settings or generic items)
        if len(detected_items) == 0 or mode == "generic":
            block_size = int(51 * (w / 768.0))
            if block_size % 2 == 0:
                block_size += 1
            block_size = max(21, block_size)
            
            c_val = int(18 * (1.3 - sensitivity))
            adapt = cv2.adaptiveThreshold(
                gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY_INV, block_size, c_val
            )
            
            k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
            adapt_clean = cv2.morphologyEx(adapt, cv2.MORPH_OPEN, k, iterations=1)
            adapt_dilated = cv2.dilate(adapt_clean, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7)), iterations=2)
            
            g_cnts, _ = cv2.findContours(adapt_dilated, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            min_g_area = 250 * (1.3 - sensitivity)
            
            for gc in g_cnts:
                area = cv2.contourArea(gc)
                if min_g_area < area < (w * h * 0.4):
                    x, y, bw, bh = cv2.boundingRect(gc)
                    # Filter frame border shadows
                    if (x < 10 or y < 10 or (x + bw) > (w - 10) or (y + bh) > (h - 10)) and area > 40000:
                        continue
                        
                    M = cv2.moments(gc)
                    cx = int(M["m10"] / M["m00"]) if M["m00"] > 0 else x + bw // 2
                    cy = int(M["m01"] / M["m00"]) if M["m00"] > 0 else y + bh // 2
                    
                    detected_items.append({
                        "id": item_id,
                        "center": [cx, cy],
                        "gem_bbox": [x, y, bw, bh],
                        "bbox": [x, y, bw, bh],
                        "contour": [],
                        "area": float(area),
                        "confidence": 0.98,
                        "type": "metallic_pin_silhouette"
                    })
                    item_id += 1
                    
        return {
            "count": len(detected_items),
            "items": detected_items,
            "processed_width": w,
            "processed_height": h
        }

    def draw_annotations(self, image_bgr: np.ndarray, results: Dict[str, Any]) -> np.ndarray:
        """Draw neon bounding boxes, center dots, ID tags, and HUD counter."""
        annotated = image_bgr.copy()
        for item in results.get("items", []):
            x, y, w, h = item["bbox"]
            cx, cy = item["center"]
            item_id = item["id"]
            
            # Neon Green Box
            cv2.rectangle(annotated, (x, y), (x + w, y + h), (157, 255, 0), 2)
            # Center Target Dot
            cv2.circle(annotated, (cx, cy), 6, (85, 0, 255), -1)
            cv2.circle(annotated, (cx, cy), 8, (255, 255, 255), 1)
            
            # Number Label
            label = f"#{item_id}"
            cv2.putText(annotated, label, (x, max(20, y - 6)), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (157, 255, 0), 2)
            
        count = results.get("count", 0)
        hud_text = f"Count: {count} pcs"
        cv2.putText(annotated, hud_text, (20, 45), cv2.FONT_HERSHEY_SIMPLEX, 1.1, (0, 0, 0), 4)
        cv2.putText(annotated, hud_text, (20, 45), cv2.FONT_HERSHEY_SIMPLEX, 1.1, (157, 255, 0), 2)
        
        return annotated
