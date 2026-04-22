from __future__ import annotations

from datetime import UTC, datetime
import hashlib
import hmac
import json

import requests


def _timestamp() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def deliver_webhook(
    payload: dict,
    *,
    webhook_url: str,
    webhook_secret: str | None,
    timeout_seconds: int,
) -> dict:
    attempted_at = _timestamp()
    body = json.dumps(payload).encode("utf-8")
    headers = {
        "Content-Type": "application/json",
        "X-Model-Service-Job-Id": str(payload["job_id"]),
    }
    if webhook_secret:
        signature = hmac.new(
            webhook_secret.encode("utf-8"),
            body,
            hashlib.sha256,
        ).hexdigest()
        headers["X-Model-Service-Signature-256"] = f"sha256={signature}"

    try:
        response = requests.post(
            webhook_url,
            data=body,
            headers=headers,
            timeout=timeout_seconds,
        )
        return {
            "attempted_at": attempted_at,
            "success": response.ok,
            "status_code": response.status_code,
            "error": None if response.ok else response.text[:500],
        }
    except Exception as exc:
        return {
            "attempted_at": attempted_at,
            "success": False,
            "status_code": None,
            "error": str(exc),
        }
