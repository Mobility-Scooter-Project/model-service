from __future__ import annotations

import json
import logging
import mimetypes
import os
from pathlib import Path
from urllib.parse import urlparse

from dotenv import load_dotenv
import requests

from ..config import get_settings
from ..jobs.queue import acknowledge_job, claim_next_job, create_queue_client, recover_processing_jobs
from ..jobs.redis_store import (
    create_job_store,
    job_status_response,
    mark_failed,
    mark_running,
    mark_succeeded,
    record_webhook_delivery,
)
from ..model import create_model
from ..storage.s3 import create_blob_store
from ..webhooks.delivery import deliver_webhook

load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s - %(message)s")
logger = logging.getLogger(__name__)


def _download_input(get_url: str, job_id: str, temp_dir: str) -> str:
    response = requests.get(get_url, stream=True, timeout=60)
    response.raise_for_status()

    parsed = urlparse(get_url)
    ext = Path(parsed.path).suffix
    if not ext:
        content_type = response.headers.get("Content-Type", "").split(";")[0].strip()
        ext = mimetypes.guess_extension(content_type) or ".bin"

    Path(temp_dir).mkdir(parents=True, exist_ok=True)
    file_path = Path(temp_dir) / f"{job_id}{ext}"
    with file_path.open("wb") as handle:
        for chunk in response.iter_content(chunk_size=8192):
            if chunk:
                handle.write(chunk)
    return str(file_path)


def _upload_result(put_url: str, payload: dict) -> None:
    response = requests.put(
        put_url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        timeout=120,
    )
    response.raise_for_status()


def _send_webhook(job_store, blob_store, settings, job):
    if not job.get("webhook_url"):
        return

    result_get_url = None
    expires_at = None
    if job["status"] == "succeeded":
        result_get_url, expires_at = blob_store.generate_get_url(
            job["result_object_key"],
            expires_seconds=settings.result_get_url_ttl_seconds,
        )

    payload = job_status_response(
        job,
        result_get_url=result_get_url,
        result_url_expires_at=expires_at,
    ).model_dump(mode="json", by_alias=True)
    delivery = deliver_webhook(
        payload,
        webhook_url=job["webhook_url"],
        webhook_secret=job.get("webhook_secret"),
        timeout_seconds=settings.webhook_timeout_seconds,
    )
    record_webhook_delivery(job_store, job["job_id"], **delivery)


def main() -> None:
    settings = get_settings()
    queue_client = create_queue_client(settings.redis_url)
    job_store = create_job_store(
        settings.redis_url,
        prefix=settings.redis_key_prefix,
        ttl_seconds=settings.job_ttl_seconds,
    )
    blob_store = create_blob_store(settings)
    blob_store.ensure_bucket()

    model = create_model(settings.model_name)
    logger.info("Loading model %s for worker role", settings.model_name)
    model.load_model()

    stale_jobs = recover_processing_jobs(queue_client, settings.redis_key_prefix, settings.model_name)
    for stale_job_id in stale_jobs:
        logger.warning("Marking stale processing job %s as failed after worker restart", stale_job_id)
        try:
            stale_job = mark_failed(
                job_store,
                stale_job_id,
                "Worker restarted before the job completed.",
            )
            _send_webhook(job_store, blob_store, settings, stale_job)
        except ValueError:
            logger.warning("Skipping stale job %s because the metadata record no longer exists", stale_job_id)

    while True:
        job_id = claim_next_job(
            queue_client,
            settings.redis_key_prefix,
            settings.model_name,
            settings.queue_block_timeout_seconds,
        )
        if job_id is None:
            continue

        local_input_path = None
        try:
            job = job_store.get_job(job_id)
            if job is None:
                logger.warning("Dropping queued job %s because its metadata record has expired", job_id)
                acknowledge_job(queue_client, settings.redis_key_prefix, settings.model_name, job_id)
                continue

            job = mark_running(job_store, job_id)
            logger.info("Processing job %s", job_id)
            local_input_path = _download_input(job["get_url"], job_id, settings.worker_temp_dir)
            result = model.predict(local_input_path, job.get("fields") or model.output_fields)

            if result.get("error"):
                raise RuntimeError(result["error"]["message"])

            _upload_result(job["result_put_url"], result)
            job = mark_succeeded(job_store, job_id)
            _send_webhook(job_store, blob_store, settings, job)
            logger.info("Job %s completed successfully", job_id)
        except Exception as exc:
            logger.exception("Job %s failed", job_id)
            try:
                job = mark_failed(job_store, job_id, str(exc))
                _send_webhook(job_store, blob_store, settings, job)
            except ValueError:
                logger.warning("Unable to persist failure metadata for job %s because it no longer exists", job_id)
        finally:
            if local_input_path and os.path.exists(local_input_path):
                os.remove(local_input_path)
            acknowledge_job(queue_client, settings.redis_key_prefix, settings.model_name, job_id)


if __name__ == "__main__":
    main()
