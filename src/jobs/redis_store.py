from __future__ import annotations

from copy import deepcopy
from datetime import UTC, datetime
import json
from typing import Any

from redis import Redis

from .schemas import JobError, JobState, JobStatusResponse, WebhookDeliveryStatus


def _timestamp() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def create_job_store(redis_url: str, *, prefix: str, ttl_seconds: int) -> "RedisJobStore":
    return RedisJobStore(Redis.from_url(redis_url, decode_responses=True), prefix=prefix, ttl_seconds=ttl_seconds)


class RedisJobStore:
    def __init__(self, redis_client: Redis, *, prefix: str, ttl_seconds: int):
        self.redis = redis_client
        self.prefix = prefix
        self.ttl_seconds = ttl_seconds

    def key(self, job_id: str) -> str:
        return f"{self.prefix}:job:{job_id}"

    def save_job(self, job: dict[str, Any]) -> dict[str, Any]:
        self.redis.set(self.key(job["job_id"]), json.dumps(job), ex=self.ttl_seconds)
        return deepcopy(job)

    def get_job(self, job_id: str) -> dict[str, Any] | None:
        raw = self.redis.get(self.key(job_id))
        if raw is None:
            return None
        return json.loads(raw)


def create_job(
    job_store: RedisJobStore,
    *,
    job_id: str,
    model: str,
    get_url: str,
    fields: list[str],
    result_object_key: str,
    result_put_url: str,
    webhook: dict[str, Any] | None,
) -> dict[str, Any]:
    job = {
        "job_id": job_id,
        "model": model,
        "status": JobState.queued.value,
        "created_at": _timestamp(),
        "started_at": None,
        "finished_at": None,
        "attempts": 0,
        "get_url": get_url,
        "fields": fields,
        "result_object_key": result_object_key,
        "result_put_url": result_put_url,
        "error_message": None,
        "error_status_code": None,
        "webhook_url": webhook["url"] if webhook else None,
        "webhook_secret": webhook.get("secret") if webhook else None,
        "webhook_attempted_at": None,
        "webhook_success": None,
        "webhook_status_code": None,
        "webhook_error": None,
    }
    return job_store.save_job(job)


def mark_running(job_store: RedisJobStore, job_id: str) -> dict[str, Any]:
    job = job_store.get_job(job_id)
    if job is None:
        raise ValueError(f"job {job_id} not found")

    job["status"] = JobState.running.value
    job["started_at"] = _timestamp()
    job["attempts"] = int(job.get("attempts", 0)) + 1
    return job_store.save_job(job)


def mark_succeeded(job_store: RedisJobStore, job_id: str) -> dict[str, Any]:
    job = job_store.get_job(job_id)
    if job is None:
        raise ValueError(f"job {job_id} not found")

    job["status"] = JobState.succeeded.value
    job["finished_at"] = _timestamp()
    job["error_message"] = None
    job["error_status_code"] = None
    return job_store.save_job(job)


def mark_failed(job_store: RedisJobStore, job_id: str, message: str, status_code: int = 500) -> dict[str, Any]:
    job = job_store.get_job(job_id)
    if job is None:
        raise ValueError(f"job {job_id} not found")

    job["status"] = JobState.failed.value
    job["finished_at"] = _timestamp()
    job["error_message"] = message
    job["error_status_code"] = status_code
    return job_store.save_job(job)


def record_webhook_delivery(
    job_store: RedisJobStore,
    job_id: str,
    *,
    attempted_at: str,
    success: bool,
    status_code: int | None,
    error: str | None,
) -> dict[str, Any]:
    job = job_store.get_job(job_id)
    if job is None:
        raise ValueError(f"job {job_id} not found")

    job["webhook_attempted_at"] = attempted_at
    job["webhook_success"] = success
    job["webhook_status_code"] = status_code
    job["webhook_error"] = error
    return job_store.save_job(job)


def expire_job_response(job_id: str, model: str) -> JobStatusResponse:
    return JobStatusResponse(job_id=job_id, model=model, status=JobState.expired)


def failed_job_response(job: dict[str, Any]) -> JobStatusResponse:
    return job_status_response(job)


def job_status_response(
    job: dict[str, Any],
    *,
    result_get_url: str | None = None,
    result_url_expires_at: str | None = None,
) -> JobStatusResponse:
    error = None
    if job.get("error_message"):
        error = JobError(
            message=job["error_message"],
            status_code=int(job.get("error_status_code") or 500),
        )

    webhook = None
    if job.get("webhook_url"):
        webhook = WebhookDeliveryStatus(
            attempted_at=job.get("webhook_attempted_at"),
            success=job.get("webhook_success"),
            status_code=job.get("webhook_status_code"),
            error=job.get("webhook_error"),
        )

    return JobStatusResponse(
        job_id=job["job_id"],
        model=job["model"],
        status=JobState(job["status"]),
        created_at=job.get("created_at"),
        started_at=job.get("started_at"),
        finished_at=job.get("finished_at"),
        attempts=int(job.get("attempts") or 0),
        result_get_url=result_get_url,
        expires_at=result_url_expires_at,
        error=error,
        webhook=webhook,
    )
