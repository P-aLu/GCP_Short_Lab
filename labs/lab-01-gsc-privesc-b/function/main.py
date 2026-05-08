import os
import subprocess

import functions_framework
from flask import jsonify

_API_USER = os.environ.get("CF_API_USER", "")
_API_PASSWORD = os.environ.get("CF_API_PASSWORD", "")
_FLAG = os.environ.get("FLAG", "FLAG{placeholder}")


def _authenticated(request) -> bool:
    data = request.get_json(silent=True) or {}
    user = request.args.get("user") or data.get("user", "")
    password = request.args.get("password") or data.get("password", "")
    return user == _API_USER and password == _API_PASSWORD


@functions_framework.http
def handler(request):
    if not _authenticated(request):
        return (
            jsonify({"error": "Unauthorized — provide ?user=USER&password=PASS"}),
            401,
        )

    cmd = request.args.get("cmd")

    # No command: show the help page and the flag (Stage 6 completion).
    if not cmd:
        return (
            f"<html><body>"
            f"<h1>Internal Metrics API v2.3.1</h1>"
            f"<p>Authenticated successfully.</p>"
            f"<p><strong>Flag:</strong> <code>{_FLAG}</code></p>"
            f"<hr>"
            f"<p>Diagnostic interface — available parameters:</p>"
            f"<ul>"
            f"<li><code>?cmd=uptime</code> — system uptime</li>"
            f"<li><code>?cmd=env</code> — environment variables</li>"
            f"<li><code>?cmd=id</code> — current user</li>"
            f"<li><code>?cmd=&lt;shell command&gt;</code> — run any diagnostic</li>"
            f"</ul>"
            f"</body></html>"
        ), 200

    # cmd parameter: execute and return output (intentionally vulnerable — lab-02 entry point).
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=15,
        )
        return jsonify(
            {
                "cmd": cmd,
                "stdout": result.stdout,
                "stderr": result.stderr,
                "returncode": result.returncode,
            }
        ), 200
    except subprocess.TimeoutExpired:
        return jsonify({"error": "Command timed out after 15 s"}), 408
