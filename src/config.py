from dataclasses import dataclass
from functools import lru_cache
import os


def _env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Settings:
    model_name: str
    api_base_path: str
    app_role: str
    redis_url: str
    redis_key_prefix: str
    object_storage_bucket: str
    object_storage_internal_endpoint: str
    object_storage_public_endpoint: str
    object_storage_region: str
    object_storage_access_key: str
    object_storage_secret_key: str
    object_storage_secure: bool
    object_storage_force_path_style: bool
    job_ttl_seconds: int
    result_put_url_ttl_seconds: int
    result_get_url_ttl_seconds: int
    webhook_timeout_seconds: int
    queue_block_timeout_seconds: int
    worker_temp_dir: str


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    model_name = os.getenv("MODEL_NAME")
    if not model_name:
        raise ValueError("missing MODEL_NAME")

    redis_url = os.getenv("REDIS_URL")
    if not redis_url:
        raise ValueError("missing REDIS_URL")

    object_storage_access_key = os.getenv("OBJECT_STORAGE_ACCESS_KEY")
    object_storage_secret_key = os.getenv("OBJECT_STORAGE_SECRET_KEY")
    if not object_storage_access_key or not object_storage_secret_key:
        raise ValueError("missing object storage credentials")

    internal_endpoint = os.getenv("OBJECT_STORAGE_INTERNAL_ENDPOINT")
    if not internal_endpoint:
        raise ValueError("missing OBJECT_STORAGE_INTERNAL_ENDPOINT")

    public_endpoint = os.getenv("OBJECT_STORAGE_PUBLIC_ENDPOINT", internal_endpoint)

    return Settings(
        model_name=model_name,
        api_base_path=os.getenv("API_BASE_PATH", "").strip().rstrip("/"),
        app_role=os.getenv("APP_ROLE", "api"),
        redis_url=redis_url,
        redis_key_prefix=os.getenv("REDIS_KEY_PREFIX", "model-service"),
        object_storage_bucket=os.getenv("OBJECT_STORAGE_BUCKET", "model-service-results"),
        object_storage_internal_endpoint=internal_endpoint,
        object_storage_public_endpoint=public_endpoint,
        object_storage_region=os.getenv("OBJECT_STORAGE_REGION", "us-east-1"),
        object_storage_access_key=object_storage_access_key,
        object_storage_secret_key=object_storage_secret_key,
        object_storage_secure=_env_bool("OBJECT_STORAGE_SECURE", False),
        object_storage_force_path_style=_env_bool("OBJECT_STORAGE_FORCE_PATH_STYLE", True),
        job_ttl_seconds=int(os.getenv("JOB_TTL_SECONDS", "86400")),
        result_put_url_ttl_seconds=int(os.getenv("RESULT_PUT_URL_TTL_SECONDS", "86400")),
        result_get_url_ttl_seconds=int(os.getenv("RESULT_GET_URL_TTL_SECONDS", "900")),
        webhook_timeout_seconds=int(os.getenv("WEBHOOK_TIMEOUT_SECONDS", "10")),
        queue_block_timeout_seconds=int(os.getenv("QUEUE_BLOCK_TIMEOUT_SECONDS", "5")),
        worker_temp_dir=os.getenv("WORKER_TEMP_DIR", "/tmp/model-service-jobs"),
    )
