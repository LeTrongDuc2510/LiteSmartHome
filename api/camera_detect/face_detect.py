import cv2
import numpy as np
from tensorflow.keras.models import load_model
from PIL import Image, ImageOps
import time
import json
import requests

# Load the model and labels
model = load_model("camera_detect/keras_model.h5", compile=False)
class_names = [line.strip()[2:] for line in open("camera_detect/labels.txt", "r").readlines()]  # skip index like "0 ClassName"
camera = cv2.VideoCapture(0)

# Face detector
face_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")

# Define your "correct" label
AUTHORIZED_PERSON = "Tuan"

# Cooldown settings
cooldown_seconds = 5
last_trigger_time = 0
last_seen_time = 0  # new

import threading


def post_switch_state(_is_switched):
    # Load token from the JSON file
    with open('../assets/token.json', 'r') as f:
        token_data = json.load(f)
    
    jwt_token = token_data['jwtToken']
    entity_id = token_data['device_id']

    url = f'https://app.coreiot.io/api/rpc/oneway/{entity_id}'

    headers = {
        'Content-Type': 'application/json',
        'X-Authorization': f'Bearer {jwt_token}',
    }

    body = {
        "method": "setServoAngle",
        "params": _is_switched,
        "persistent": False,
        "timeout": 500
    }

    response = requests.post(url, headers=headers, json=body)

    if response.status_code == 200:
        print('Switch state posted successfully')
    else:
        print(f'Failed to post switch state: {response.status_code}, {response.text}')



servo_open = False
servo_timer = None

def trigger_servo():
    global servo_open, servo_timer
    print("🔓 Servo opened!")
    servo_open = True
    post_switch_state(servo_open)


def close_servo():
    global servo_open
    if servo_open:
        print("🔒 Servo closed.")
        servo_open = False
        post_switch_state(servo_open)

# Preprocess for Teachable Machine model
def preprocess_face(roi):
    image = Image.fromarray(cv2.cvtColor(roi, cv2.COLOR_BGR2RGB))
    image = ImageOps.fit(image, (224, 224), Image.Resampling.LANCZOS)
    image_array = np.asarray(image).astype(np.float32)
    normalized_image_array = (image_array / 127.5) - 1  # Teachable Machine normalization
    return np.expand_dims(normalized_image_array, axis=0)

def monitor_presence():
    global servo_open, last_seen_time
    while True:
        time.sleep(1)
        if servo_open and time.time() - last_seen_time > 5:
            close_servo()

# Video stream generator
# def generate_frames():
#     global last_trigger_time  # <-- Add this line
#     frame_count = 0
#     last_prediction = None
#     last_faces = []

#     target_fps = 90  # desired FPS to stream
#     frame_duration = 1.0 / target_fps

#     threading.Thread(target=monitor_presence, daemon=True).start()

#     while True:
#         start_time = time.time()
#         success, frame = camera.read()
#         if not success:
#             break

#         frame_count += 1

#         if frame_count % 2 == 0:  # Process every 3rd frame
#             gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
#             faces = face_cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5)
            
#             last_faces = faces
#             last_prediction = []

#             for (x, y, w, h) in faces:
#                 roi = frame[y:y+h, x:x+w]
#                 input_data = preprocess_face(roi)
#                 prediction = model.predict(input_data)
#                 index = np.argmax(prediction)
#                 label = class_names[index]
#                 confidence = prediction[0][index]
#                 last_prediction.append((x, y, w, h, label, confidence))

#                 if label == AUTHORIZED_PERSON and confidence > 0.8:
#                     current_time = time.time()
#                     global last_seen_time 
#                     last_seen_time = current_time  # 👈 update the last time you were seen

#                     if not servo_open:
#                         trigger_servo()
#         else:
#             # Reuse last prediction and draw
#             for (x, y, w, h, label, confidence) in last_prediction or []:
#                 color = (0, 255, 0) if confidence > 0.8 else (0, 0, 255)
#                 cv2.rectangle(frame, (x, y), (x+w, y+h), color, 2)
#                 cv2.putText(frame, f'{label} ({confidence:.2f})', (x, y-10),
#                             cv2.FONT_HERSHEY_SIMPLEX, 0.8, color, 2)

#         ret, buffer = cv2.imencode('.jpg', frame)
#         frame = buffer.tobytes()
#         yield (b'--frame\r\n'
#                b'Content-Type: image/jpeg\r\n\r\n' + frame + b'\r\n')
        
#         # Sleep to maintain target FPS
#         elapsed = time.time() - start_time
#         sleep_time = frame_duration - elapsed
#         if sleep_time > 0:
#             time.sleep(sleep_time)

def generate_frames():
    global last_trigger_time
    frame_count = 0
    last_prediction = None
    last_faces = []

    target_fps = 30
    frame_duration = 1.0 / target_fps

    threading.Thread(target=monitor_presence, daemon=True).start()

    while True:
        start_time = time.time()
        success, frame = camera.read()
        if not success:
            break

        frame_count += 1

        if frame_count % 2 == 0:
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            faces = face_cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5)
            last_faces = faces

            input_data = preprocess_face(frame) 
            prediction = model.predict(input_data)
            index = np.argmax(prediction)
            label = class_names[index]
            confidence = prediction[0][index]
            last_prediction = (label, confidence)

            if label == AUTHORIZED_PERSON and confidence > 0.8:
                current_time = time.time()
                global last_seen_time
                last_seen_time = current_time
                if not servo_open:
                    trigger_servo()
        else:
            label, confidence = last_prediction or ("Unknown", 0.0)

        # Draw face bounding boxes (for visualization only)
        for (x, y, w, h) in last_faces:
            color = (0, 255, 0) if confidence > 0.8 else (0, 0, 255)
            cv2.rectangle(frame, (x, y), (x+w, y+h), color, 2)

            # Draw prediction label at the top
            text = f'{label} ({confidence:.2f})'
            cv2.putText(frame, text, (30, 30), cv2.FONT_HERSHEY_SIMPLEX, 1, color, 2)

        ret, buffer = cv2.imencode('.jpg', frame)
        frame = buffer.tobytes()
        yield (b'--frame\r\n'
               b'Content-Type: image/jpeg\r\n\r\n' + frame + b'\r\n')

        elapsed = time.time() - start_time
        sleep_time = frame_duration - elapsed
        if sleep_time > 0:
            time.sleep(sleep_time)

