
import os
import socket
from pathlib import Path

from flask import Flask, jsonify

app = Flask(__name__)

def get_config(name):
    # Read mounted ConfigMap files dynamically when available.
    config_file = Path("/etc/app-config") / name

    if config_file.is_file():
        value = config_file.read_text().strip()
        if value:
            return value

    # Otherwise use environment variables.
    return os.getenv(name, "")


@app.route("/", methods=["GET"])
def home():
    return jsonify({
        "app": get_config("APP_NAME"),
        "version": get_config("VERSION"),
        "pod": socket.gethostname()
    })


@app.route("/healthz", methods=["GET"])
def health():
    return jsonify({"status": "healthy"}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
