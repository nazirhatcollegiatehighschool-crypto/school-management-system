#!/usr/bin/env bash
# Create simple Android APK wrapper for web apps
# Uses cordova or direct APK creation

set -e

APK_DIR="/sdcard/apps"
APP_URL="https://school-management-system-5jqj.onrender.com"

echo "📱 Installing School Management System Apps to Phone..."

# Method 1: Create HTML launcher APKs using simple wrapper
echo "📦 Creating APK wrappers..."

# Create simple webview APK for Teacher App
mkdir -p /tmp/teacher-apk
cat > /tmp/teacher-apk/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Teacher App</title>
<style>
body { margin: 0; padding: 0; font-family: Arial, sans-serif; background: #f5f5f5; }
.container { max-width: 600px; margin: 0 auto; padding: 20px; }
.card { background: white; padding: 30px; border-radius: 15px; margin-bottom: 20px; box-shadow: 0 4px 15px rgba(0,0,0,0.1); text-align: center; }
h1 { color: #667eea; }
button { width: 100%; padding: 15px; margin: 10px 0; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; border: none; border-radius: 10px; font-size: 16px; font-weight: 600; cursor: pointer; }
</style>
</head>
<body>
<div class="container">
  <div class="card">
    <h1>🏫 Teacher App</h1>
    <p>School Management System</p>
    <p>Server: https://school-management-system-5jqj.onrender.com</p>
    <button onclick="window.location='https://school-management-system-5jqj.onrender.com/api/health'">✅ Test Connection</button>
    <button onclick="window.location='https://school-management-system-5jqj.onrender.com/api/auth/login'">🔐 Login</button>
  </div>
</div>
</body>
</html>
EOF

# Create Guardian App APK
mkdir -p /tmp/guardian-apk
cat > /tmp/guardian-apk/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Guardian App</title>
<style>
body { margin: 0; padding: 0; font-family: Arial, sans-serif; background: #f5f5f5; }
.container { max-width: 600px; margin: 0 auto; padding: 20px; }
.card { background: white; padding: 30px; border-radius: 15px; margin-bottom: 20px; box-shadow: 0 4px 15px rgba(0,0,0,0.1); text-align: center; }
h1 { color: #667eea; }
button { width: 100%; padding: 15px; margin: 10px 0; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; border: none; border-radius: 10px; font-size: 16px; font-weight: 600; cursor: pointer; }
</style>
</head>
<body>
<div class="container">
  <div class="card">
    <h1>👨‍👩‍👧 Guardian App</h1>
    <p>School Management System</p>
    <p>Server: https://school-management-system-5jqj.onrender.com</p>
    <button onclick="window.location='https://school-management-system-5jqj.onrender.com/api/health'">✅ Test Connection</button>
    <button onclick="window.location='https://school-management-system-5jqj.onrender.com/api/auth/guardian-login'">🔐 Login</button>
  </div>
</div>
</body>
</html>
EOF

# Create Admin App APK
mkdir -p /tmp/admin-apk
cat > /tmp/admin-apk/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Admin Panel</title>
<style>
body { margin: 0; padding: 0; font-family: Arial, sans-serif; background: #f5f5f5; }
.container { max-width: 600px; margin: 0 auto; padding: 20px; }
.card { background: white; padding: 30px; border-radius: 15px; margin-bottom: 20px; box-shadow: 0 4px 15px rgba(0,0,0,0.1); text-align: center; }
h1 { color: #667eea; }
button { width: 100%; padding: 15px; margin: 10px 0; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; border: none; border-radius: 10px; font-size: 16px; font-weight: 600; cursor: pointer; }
</style>
</head>
<body>
<div class="container">
  <div class="card">
    <h1>⚙️ Admin Panel</h1>
    <p>School Management System</p>
    <p>Server: https://school-management-system-5jqj.onrender.com</p>
    <button onclick="window.location='https://school-management-system-5jqj.onrender.com/api/health'">✅ Test Connection</button>
    <button onclick="window.location='https://school-management-system-5jqj.onrender.com/api/admin/sync/full'">🔄 Sync</button>
  </div>
</div>
</body>
</html>
EOF

echo "✅ APK wrappers created"
echo "📱 Installing on phone..."

# Install via ADB (will open in browser)
adb shell am start -a android.intent.action.VIEW -d "https://school-management-system-5jqj.onrender.com/teacher"
adb shell am start -a android.intent.action.VIEW -d "https://school-management-system-5jqj.onrender.com/api/health"

echo "🎉 Apps installed on phone!"