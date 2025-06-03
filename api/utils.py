import json
import requests
import urllib.parse
from datetime import datetime, timedelta

def get_telemetry_interval():
    with open('../assets/token.json', 'r') as f:
        token_data = json.load(f)
    
    jwt_token = token_data['jwtToken']
    entity_id = token_data['device_id']
    keys = ['temperature', 'humidity']

    now = datetime.now()
    # start_ts = int(now.timestamp() * 1000)
    start_ts = int((now - timedelta(days=1)).timestamp() * 1000)
    end_ts = int((now + timedelta(days=1)).timestamp() * 1000)

    # print actuual timestamps
    print(f'Start Timestamp: {start_ts}, End Timestamp: {end_ts}')
    limit = 1000
    use_strict_data_types = True 
    entity_type = 'DEVICE'

    query_params = {
        'keys': ','.join(keys),
        'startTs': start_ts,
        'endTs': end_ts,
        'limit': limit,
        'useStrictDataTypes': str(use_strict_data_types).lower(),
    }

    base_url = 'https://app.coreiot.io'
    path = f'/api/plugins/telemetry/{entity_type}/{entity_id}/values/timeseries'
    query_string = urllib.parse.urlencode(query_params)

    final_url = urllib.parse.urljoin(base_url, path) + '?' + query_string

    headers = {
        'Content-Type': 'application/json',
        'X-Authorization': f'Bearer {jwt_token}',
    }
    response = requests.get(final_url, headers=headers)

    if response.status_code == 200:
        telemetry_data = response.json()
        # print(telemetry_data)
        if 'temperature' in telemetry_data and 'humidity' in telemetry_data:
            print('Temperature and humidity data found in the response.')
            temperature = telemetry_data['temperature']
            humidity = telemetry_data['humidity']
            return temperature, humidity
        else:
            print('Temperature or humidity data not found in the response.')
            return [], []
    else:
        print(f'Failed to get telemetry interval: {response.status_code}, {response.text}')
        return None

def filter_by_interval(raw_temp, raw_humid, intervalMs=900000):
    if not raw_temp or not raw_humid:
        return [], []

    # Sort both by 'ts' ascending
    paired = sorted(zip(raw_temp, raw_humid), key=lambda pair: pair[0]['ts'])

    filtered_temp = []
    filtered_humid = []
    last_ts = None

    for temp_point, humid_point in paired:
        ts = temp_point['ts']
    

        if last_ts is None or ts - last_ts >= intervalMs:
            print(f"Processing timestamp: {ts}")
            filtered_temp.append(temp_point)
            filtered_humid.append(humid_point)
            last_ts = ts

    return filtered_temp, filtered_humid

# raw_temp, raw_humid = get_telemetry_interval()
# if raw_temp is not None and raw_humid is not None:
#     filtered_temp, filtered_humid = filter_by_interval(raw_temp, raw_humid, intervalMs=1800000)
#     print("Filtered Temperature Data:", filtered_temp)
#     print("Filtered Humidity Data:", filtered_humid)
#     print(f"Number of filtered temperature points: {len(filtered_temp)}")
#     print(f"Number of filtered humidity points: {len(filtered_humid)}")