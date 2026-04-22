from redis import Redis


def create_queue_client(redis_url: str) -> Redis:
    return Redis.from_url(redis_url, decode_responses=True)


def _queue_key(prefix: str, model: str) -> str:
    return f"{prefix}:{model}:jobs"


def _processing_queue_key(prefix: str, model: str) -> str:
    return f"{prefix}:{model}:jobs:processing"


def enqueue_job(redis_client: Redis, prefix: str, model: str, job_id: str) -> int:
    return int(redis_client.lpush(_queue_key(prefix, model), job_id))


def claim_next_job(redis_client: Redis, prefix: str, model: str, timeout_seconds: int) -> str | None:
    return redis_client.brpoplpush(
        _queue_key(prefix, model),
        _processing_queue_key(prefix, model),
        timeout=timeout_seconds,
    )


def acknowledge_job(redis_client: Redis, prefix: str, model: str, job_id: str) -> int:
    return int(redis_client.lrem(_processing_queue_key(prefix, model), 1, job_id))


def recover_processing_jobs(redis_client: Redis, prefix: str, model: str) -> list[str]:
    processing_key = _processing_queue_key(prefix, model)
    job_ids = [job_id for job_id in redis_client.lrange(processing_key, 0, -1) if job_id]
    if not job_ids:
        return []

    with redis_client.pipeline() as pipe:
        for job_id in job_ids:
            pipe.lrem(processing_key, 1, job_id)
        pipe.execute()

    return job_ids
