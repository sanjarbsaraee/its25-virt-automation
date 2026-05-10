"""
ITS25 Capstone — demo Flask application.

Three endpoints:
  /       — welcome page with hostname
  /info   — JSON with hostname, timestamp, db connectivity
  /health — returns 'ok' for load balancer health checks
"""
import os
import socket
from datetime import datetime, timezone

from flask import Flask, jsonify

app = Flask(__name__)

DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = os.environ.get("DB_PORT", "5432")
DB_NAME = os.environ.get("DB_NAME", "app")
DB_USER = os.environ.get("DB_USER", "app_rw")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "changeme")


def check_db():
    """Try connecting to PostgreSQL. Returns True on success."""
    try:
        import psycopg2
        conn = psycopg2.connect(
            host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
            user=DB_USER, password=DB_PASSWORD,
            sslmode="require", connect_timeout=3,
        )
        conn.close()
        return True
    except Exception:
        return False


@app.route("/")
def index():
    hostname = socket.gethostname()
    return (
        f"<h1>ITS25 Capstone Demo</h1>"
        f"<p>Served from: <strong>{hostname}</strong></p>"
        f"<p>Database: {DB_HOST}:{DB_PORT}/{DB_NAME}</p>"
        f"<p>DB reachable: {check_db()}</p>"
    )


@app.route("/info")
def info():
    return jsonify(
        hostname=socket.gethostname(),
        timestamp=datetime.now(timezone.utc).isoformat(),
        db_host=DB_HOST,
        db_reachable=check_db(),
    )


@app.route("/health")
def health():
    return "ok\n", 200