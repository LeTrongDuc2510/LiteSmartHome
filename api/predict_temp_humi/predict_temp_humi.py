# weather_predictor.py

import time
import json
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from tensorflow.keras.models import load_model
from tensorflow.keras.losses import MeanSquaredError
from sklearn.preprocessing import MinMaxScaler
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import os
# import joblib # Bỏ comment nếu bạn dùng joblib

print(f"Module 'weather_predictor' is being imported or run.")

# --- Configuration Constants ---
N_STEPS_IN = 12
N_FEATURES = 2
N_STEPS_OUT = 96

SMTP_SERVER = 'smtp.gmail.com'
SMTP_PORT = 587
EMAIL_SENDER = 'tuan.tranhoangkhoii@hcmut.edu.vn' # Địa chỉ email người gửi
EMAIL_PASSWORD = 'guhy rafi hcqw eequ' # Mật khẩu ứng dụng hoặc mật khẩu email (nên dùng mật khẩu ứng dụng nếu có)
# EMAIL_RECIPIENT = 'khoituan65@gmail.com' # Địa chỉ email người nhận (có thể là người gửi hoặc khác)
EMAIL_RECIPIENT = 'duc.letrong2510@hcmut.edu.vn'
TEMP_ALARM_THRESHOLD = 30.0
HUMI_ALARM_THRESHOLD = 78.0

# --- Global Variables for the module ---
latest_actual_temp_for_email = None
latest_actual_humi_for_email = None
model = None
scaler_temp = None
scaler_humi = None

# --- Email Sending Function (Giữ nguyên) ---
def send_email_generic(subject, body_html, recipient=EMAIL_RECIPIENT, sender=EMAIL_SENDER, password=EMAIL_PASSWORD):
    # ... (code hàm send_email_generic như bạn đã có) ...
    try:
        msg = MIMEMultipart('alternative')
        msg['From'] = sender
        msg['To'] = recipient
        msg['Subject'] = subject
        msg.attach(MIMEText(body_html, 'html'))
        server = smtplib.SMTP(SMTP_SERVER, SMTP_PORT)
        server.starttls()
        server.login(sender, password)
        text = msg.as_string()
        server.sendmail(sender, recipient, text)
        server.quit()
        print(f"Email sent successfully to {recipient} with subject: '{subject}'")
        return True
    except Exception as e:
        print(f"Error sending email: {e}")
        return False

# --- Function to Email FULL Predictions (Giữ nguyên) ---
def send_full_prediction_email(predicted_temps_full, predicted_humis_full, prediction_start_time):
    # ... (code hàm send_full_prediction_email như bạn đã có) ...
    global latest_actual_temp_for_email, latest_actual_humi_for_email
    subject = f"Full 24-Hour Weather Prediction Report - {prediction_start_time.strftime('%Y-%m-%d %H:%M')}"
    body_html = f"<html><body><h2>Full 24-Hour Weather Prediction Report</h2>"
    body_html += f"<p>Prediction generated at: <strong>{prediction_start_time.strftime('%Y-%m-%d %H:%M:%S')}</strong></p>"
    if latest_actual_temp_for_email is not None and latest_actual_humi_for_email is not None:
        body_html += f"<h3>Based on last actual readings:</h3>"
        body_html += f"<p>Temperature: {latest_actual_temp_for_email:.2f}°C</p>"
        body_html += f"<p>Humidity: {latest_actual_humi_for_email:.2f}%</p><hr>"
    body_html += "<h3>Predicted Values (Next 24 Hours):</h3>"
    body_html += "<table border='1' style='border-collapse: collapse; width:70%;'>"
    body_html += "<tr><th>Predicted Time (Actual)</th><th>Temperature (°C)</th><th>Humidity (%)</th></tr>"
    for i in range(len(predicted_temps_full)):
        time_offset_minutes = (i + 1) * 15
        absolute_prediction_time = prediction_start_time + timedelta(minutes=time_offset_minutes)
        time_label_absolute = absolute_prediction_time.strftime("%Y-%m-%d %H:%M")
        temp = predicted_temps_full[i]
        humi = predicted_humis_full[i]
        body_html += f"<tr><td style='text-align:center;'>{time_label_absolute}</td><td style='text-align:center;'>{temp:.2f}</td><td style='text-align:center;'>{humi:.2f}</td></tr>"
    body_html += "</table></body></html>"
    send_email_generic(subject, body_html)

# --- Function to Check and Send Alarm Email (Giữ nguyên) ---
def check_and_send_alarm_email(predicted_temps_full, predicted_humis_full, temp_thresh, humi_thresh, prediction_start_time):
    # ... (code hàm check_and_send_alarm_email như bạn đã có) ...
    global latest_actual_temp_for_email, latest_actual_humi_for_email
    alarm_triggers = []
    for i in range(len(predicted_temps_full)):
        time_offset_minutes = (i + 1) * 15
        absolute_alarm_time = prediction_start_time + timedelta(minutes=time_offset_minutes)
        time_label_absolute = absolute_alarm_time.strftime("%Y-%m-%d %H:%M")
        if predicted_temps_full[i] > temp_thresh:
            alarm_triggers.append(
                f"Nhiệt độ dự đoán CAO: {predicted_temps_full[i]:.2f}°C (Ngưỡng: {temp_thresh}°C) vào lúc {time_label_absolute}"
            )
        if predicted_humis_full[i] > humi_thresh:
            alarm_triggers.append(
                f"Độ ẩm dự đoán CAO: {predicted_humis_full[i]:.2f}% (Ngưỡng: {humi_thresh}%) vào lúc {time_label_absolute}"
            )
    if alarm_triggers:
        subject = f"🚨 CẢNH BÁO THỜI TIẾT KHẨN CẤP! - {prediction_start_time.strftime('%Y-%m-%d %H:%M')} 🚨"
        body_html = f"<html><body><h2>Weather Alarm Details (Prediction from {prediction_start_time.strftime('%Y-%m-%d %H:%M:%S')}):</h2>" # ... (phần còn lại của body) ...
        body_html += "<ul>"
        for trigger in alarm_triggers:
            body_html += f"<li>{trigger}</li>"
        body_html += "</ul><hr>"
        if latest_actual_temp_for_email is not None and latest_actual_humi_for_email is not None:
            body_html += f"<p><strong>Based on last actual readings:</strong></p>"
            body_html += f"<p>Temperature: {latest_actual_temp_for_email:.2f}°C</p>"
            body_html += f"<p>Humidity: {latest_actual_humi_for_email:.2f}%</p>"
        body_html += "<h3>Summary of Full Prediction Period:</h3>" # ... (phần còn lại)
        body_html += f"<p>Max Predicted Temperature: {np.max(predicted_temps_full):.2f}°C</p>"
        body_html += f"<p>Min Predicted Temperature: {np.min(predicted_temps_full):.2f}°C</p>"
        body_html += f"<p>Max Predicted Humidity: {np.max(predicted_humis_full):.2f}%</p>"
        body_html += f"<p>Min Predicted Humidity: {np.min(predicted_humis_full):.2f}%</p>"
        body_html += "</body></html>"
        send_email_generic(subject, body_html)
        print(f"ALARM EMAIL SENT due to: {', '.join(alarm_triggers)}")

# --- Function to Load Model and Scalers ---
def load_resources(model_file_path, csv_for_scaler_fit_path, temp_col, humi_col):
    global model, scaler_temp, scaler_humi
    print(f"Attempting to load model from: {model_file_path}")
    try:
        model = load_model(model_file_path, custom_objects={'mse': MeanSquaredError()})
        print("Model loaded successfully.")

        print(f"Fitting scalers using data from '{csv_for_scaler_fit_path}' (NOTE: Ideally, load pre-fitted scalers).")
        df_for_scaler = pd.read_csv(csv_for_scaler_fit_path)
        
        if temp_col not in df_for_scaler.columns or humi_col not in df_for_scaler.columns:
            print(f"FATAL: One or both columns ('{temp_col}', '{humi_col}') not found in CSV for scaler fitting. Available: {df_for_scaler.columns.tolist()}")
            return False

        scaler_temp = MinMaxScaler(feature_range=(0, 1))
        scaler_humi = MinMaxScaler(feature_range=(0, 1))
        
        scaler_temp.fit(df_for_scaler[[temp_col]].astype(float))
        scaler_humi.fit(df_for_scaler[[humi_col]].astype(float))
        print(f"Scalers fitted for this session using columns: '{temp_col}' and '{humi_col}'.")
        return True

    except FileNotFoundError:
        print(f"FATAL: Model file '{model_file_path}' or CSV file '{csv_for_scaler_fit_path}' not found.")
        return False
    except KeyError as e:
        print(f"FATAL: KeyError during scaler fitting. Column not found: {e}. Ensure '{temp_col}' and '{humi_col}' are correct.")
        return False
    except Exception as e:
        print(f"Error during model/scaler setup: {e}")
        import traceback
        traceback.print_exc()
        return False

# --- Core Prediction Function ---
def get_weather_predictions(raw_temp_sequence, raw_humi_sequence, send_email=True):
    global model, scaler_temp, scaler_humi
    global latest_actual_temp_for_email, latest_actual_humi_for_email

    if model is None or scaler_temp is None or scaler_humi is None:
        print("Model or scalers not loaded. Call load_resources() first. Cannot make prediction.")
        return None, None

    if not (isinstance(raw_temp_sequence, list) and isinstance(raw_humi_sequence, list)):
        print("Error: Input temperature and humidity must be lists.")
        return None, None
        
    if len(raw_temp_sequence) != N_STEPS_IN or len(raw_humi_sequence) != N_STEPS_IN:
        print(f"Error: Input sequences must have exactly {N_STEPS_IN} values.")
        print(f"Received temp length: {len(raw_temp_sequence)}, humi length: {len(raw_humi_sequence)}")
        return None, None

    prediction_initiation_time = datetime.now()

    current_time_str_display = prediction_initiation_time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"\n--- Performing prediction at {current_time_str_display} ---")
    try:
        latest_actual_temp_for_email = float(raw_temp_sequence[-1])
        latest_actual_humi_for_email = float(raw_humi_sequence[-1])
        temp_seq_raw_np = np.array(raw_temp_sequence).astype(float)
        humi_seq_raw_np = np.array(raw_humi_sequence).astype(float)
        temp_seq_scaled = scaler_temp.transform(temp_seq_raw_np.reshape(-1, 1)).flatten()
        humi_seq_scaled = scaler_humi.transform(humi_seq_raw_np.reshape(-1, 1)).flatten()
        x_input_scaled = np.vstack((humi_seq_scaled, temp_seq_scaled)).T 
        x_input_scaled = x_input_scaled.reshape((1, N_STEPS_IN, N_FEATURES))
        predicted_values_scaled = model.predict(x_input_scaled, verbose=0)
        humi_predictions_scaled = predicted_values_scaled[0, :, 0].reshape(-1, 1)
        temp_predictions_scaled = predicted_values_scaled[0, :, 1].reshape(-1, 1)
        predicted_humis_actual = scaler_humi.inverse_transform(humi_predictions_scaled).flatten().tolist()
        predicted_temps_actual = scaler_temp.inverse_transform(temp_predictions_scaled).flatten().tolist()
        print(f"Prediction successful. First predicted Temp (T+15min): {predicted_temps_actual[0]:.2f}°C, Humi: {predicted_humis_actual[0]:.2f}%")
        if send_email:
            send_full_prediction_email(predicted_temps_actual, predicted_humis_actual, prediction_initiation_time)
            check_and_send_alarm_email(predicted_temps_actual, predicted_humis_actual, 
                                    TEMP_ALARM_THRESHOLD, HUMI_ALARM_THRESHOLD, prediction_initiation_time)
        return predicted_temps_actual, predicted_humis_actual
    except Exception as e:
        print(f"Error during prediction or emailing: {e}")
        import traceback
        traceback.print_exc()
        return None, None
    
def run_application(current_temperatures, current_humidities, send_email=True):
    print("--- Starting Main Application ---")

    # --- Cấu hình đường dẫn và tên cột (có thể lấy từ file config, v.v.) ---
    model_file_path = 'predict_temp_humi/predict_temp_humi.h5' # Đường dẫn đến file model đã lưu
    csv_path_for_scalers = 'predict_temp_humi/data.csv' # Đường dẫn đến file CSV chứa dữ liệu để tạo scalers
    temperature_column_name = 'temperature' 
    humidity_column_name = 'humidity'

    # 1. Tải tài nguyên (model và scalers) MỘT LẦN khi ứng dụng bắt đầu
    print("Loading resources from weather_predictor module...")
    if not load_resources(model_file_path, csv_path_for_scalers, temperature_column_name, humidity_column_name):
        print("Failed to load resources. Exiting application.")
        return

    # Đảm bảo dữ liệu đầu vào có đúng độ dài yêu cầu
    if len(current_temperatures) == N_STEPS_IN and \
       len(current_humidities) == N_STEPS_IN:
        
        print("\n--- Calling get_weather_predictions from main_app.py ---")
        # 3. Gọi hàm dự đoán từ module đã import
        predicted_temps, predicted_humis = get_weather_predictions(current_temperatures, current_humidities, send_email=send_email)

        # 4. Xử lý kết quả dự đoán
        if predicted_temps and predicted_humis:
            print("\n--- Predictions Received in main_app.py ---")
            print(f"Number of temperature predictions: {len(predicted_temps)}")
            print(f"First predicted temperature (T+15min): {predicted_temps[0]:.2f}°C")
            print(f"Number of humidity predictions: {len(predicted_humis)}")
            print(f"First predicted humidity (T+15min): {predicted_humis[0]:.2f}%")
            
            # Bạn có thể làm gì đó khác với predicted_temps và predicted_humis ở đây
            # Ví dụ: lưu vào database, hiển thị trên giao diện người dùng, v.v.

            return predicted_temps, predicted_humis
        else:
            print("Failed to get predictions from weather_predictor module.")
    else:
        print(f"Error in main_app: Input data does not have the required length of {N_STEPS_IN}.")

    print("\n--- Main Application Finished ---")