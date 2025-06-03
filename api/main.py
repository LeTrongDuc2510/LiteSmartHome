
import os
import json
import time
import socket
from flask import Flask, Response
from flask_cors import CORS
from apscheduler.schedulers.background import BackgroundScheduler

import predict_temp_humi.predict_temp_humi as pred_stats_model
import camera_detect.face_detect as face_detect_model
import utils as utils

app = Flask(__name__)
CORS(app)

def update_ip_config():
    """
    Update the local IP address in the token.json file.
    This function retrieves the local IP address and updates it in the configuration file.
    """
    try:
        with open('../assets/token.json', 'r') as f:
            config = json.load(f)
    except FileNotFoundError:
        config = {}

    hostname = socket.gethostname()
    local_ip = socket.gethostbyname(hostname)
    config['local_ip'] = local_ip

    with open('../assets/token.json', 'w') as f:
        json.dump(config, f, indent=4)

@app.route('/')
def hello():
    return 'Hello, World!'

@app.route('/video')
def video():
    return Response(face_detect_model.generate_frames(), mimetype='multipart/x-mixed-replace; boundary=frame')

@app.route('/pred_stats') # a get respose for prediction statistics
def pred_stat():
    current_temperatures = [30.0, 30.1, 30.0, 30.2, 30.3, 30.1, 30.0, 30.9, 30.0, 30.1, 30.2, 30.3]
    current_humidities = [65.0, 65.2, 65.1, 65.3, 65.5, 65.4, 65.2, 65.1, 65.0, 65.2, 65.3, 65.5] 

    # take real data
    # raw_temperatures, raw_humidities = utils.get_telemetry_interval()
    # if not current_temperatures or not current_humidities:
    #     return {
    #         "error": "No telemetry data available"
    #     }
    # filter by interval
    # current_temperatures, current_humidities = utils.filter_by_interval(raw_temperatures, raw_humidities)


    pred_humid_list, pred_temp_list = pred_stats_model.run_application(current_temperatures, current_humidities, send_email=False) # this reload many times hence not send email


    # this would be replaced with actual prediction logic

    return {
        "pred_humid_list": pred_humid_list,
        "pred_temp_list": pred_temp_list
    }

def send_daily_email():
    with app.app_context():
        current_temperatures = [30.0, 30.1, 30.0, 30.2, 30.3, 30.1, 30.0, 30.9, 30.0, 30.1, 30.2, 30.3]
        current_humidities = [65.0, 65.2, 65.1, 65.3, 65.5, 65.4, 65.2, 65.1, 65.0, 65.2, 65.3, 65.5] 

        # take real data
        pred_humid_list, pred_temp_list = pred_stats_model.run_application(current_temperatures, current_humidities, send_email=True) # this reload many times hence not send email
        

if __name__ == '__main__':
    # Avoid scheduler duplication in Flask debug mode
    if not app.debug or os.environ.get("WERKZEUG_RUN_MAIN") == "true":
        scheduler = BackgroundScheduler()
        # scheduler.add_job(func=send_daily_email, trigger="interval", days=1)
        scheduler.add_job(func=send_daily_email, trigger="interval", minutes=1)  # For testing, run every 30 minutes

        scheduler.start()

        import atexit
        atexit.register(lambda: scheduler.shutdown())

    update_ip_config()
    app.run(host='0.0.0.0', port=5000, debug=True)
