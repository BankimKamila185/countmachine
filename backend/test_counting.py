import cv2
import sys
import time
from pin_counter import PinCounter

def main():
    print("="*60)
    print(" 🔍 PRODUCT COUNT SCANNER - LIVE OPENCV TEST")
    print("="*60)
    
    counter = PinCounter()
    
    # Try opening default camera (0) or secondary (1)
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("⚠️ Camera index 0 could not be opened, trying index 1...")
        cap = cv2.VideoCapture(1)
        
    if not cap.isOpened():
        print("❌ No webcam found. You can test by passing an image file path:")
        print("   python test_counting.py path/to/product_image.jpg")
        return

    print("✅ Camera opened successfully!")
    print("Press 'q' in the window to quit, '+' / '-' to adjust sensitivity.")
    
    sensitivity = 0.5
    last_count = -1
    
    while True:
        ret, frame = cap.read()
        if not ret:
            print("Failed to grab frame.")
            break
            
        results = counter.process_frame(frame, sensitivity=sensitivity)
        count = results["count"]
        
        # Draw bounding boxes and HUD
        annotated = counter.draw_annotations(frame, results)
        
        # Display sensitivity info
        cv2.putText(annotated, f"Sens: {int(sensitivity*100)}%", (20, annotated.shape[0] - 20), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (200, 200, 200), 1)
        
        cv2.imshow("Product Count Scanner AI", annotated)
        
        if count != last_count:
            print(f"👉 Current Count: {count} pieces detected")
            last_count = count
            
        key = cv2.waitKey(1) & 0xFF
        if key == ord('q'):
            break
        elif key == ord('+') or key == ord('='):
            sensitivity = min(1.0, sensitivity + 0.05)
            print(f"Sensitivity: {int(sensitivity*100)}%")
        elif key == ord('-') or key == ord('_'):
            sensitivity = max(0.1, sensitivity - 0.05)
            print(f"Sensitivity: {int(sensitivity*100)}%")
            
    cap.release()
    cv2.destroyAllWindows()

if __name__ == "__main__":
    if len(sys.argv) > 1:
        img_path = sys.argv[1]
        counter = PinCounter()
        img = cv2.imread(img_path)
        if img is None:
            print(f"Error: Could not read image from {img_path}")
            sys.exit(1)
        res = counter.process_frame(img)
        print(f"Result on {img_path}:")
        print(f"Total Count: {res['count']}")
        for item in res["items"]:
            print(f" - #{item['id']} at {item['center']} (box: {item['bbox']}, conf: {item['confidence']:.2f})")
    else:
        main()
