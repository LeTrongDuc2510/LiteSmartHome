# main_app.py
import predict_temp_humi # Import file chứa logic dự đoán (đặt cùng thư mục hoặc trong PYTHONPATH)

if __name__ == "__main__":
    # Giả sử bạn có dữ liệu đầu vào từ cảm biến hoặc nguồn khác
    current_temperatures = [30.0, 30.1, 30.0, 30.2, 30.3, 30.1, 30.0, 30.9, 30.0, 30.1, 30.2, 30.3] # Ví dụ: 12 giá trị nhiệt độ
    current_humidities = [65.0, 65.2, 65.1, 65.3, 65.5, 65.4, 65.2, 65.1, 65.0, 65.2, 65.3, 65.5] # Ví dụ: 12 giá trị độ ẩm
    # Chạy ứng dụng với dữ liệu đầu vào
    # predict_temp_humi.run_application(current_temperatures, current_humidities)
    pred_humid_list, pred_temp_list = predict_temp_humi.run_application(current_temperatures, current_humidities)
    print("Dự đoán độ ẩm:", pred_humid_list)
    print("Dự đoán nhiệt độ:", pred_temp_list)