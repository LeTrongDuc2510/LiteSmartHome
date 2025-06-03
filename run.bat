@echo off
echo Starting Flask API...
start cmd /k "cd api && python main.py"

timeout /t 5 /nobreak >nul
echo Starting Flutter app...
flutter run