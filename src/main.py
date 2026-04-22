from dotenv import load_dotenv
from fastapi import APIRouter, FastAPI, Request, status
from fastapi.responses import JSONResponse
from uuid import uuid4

from .config import get_settings
from .jobs.queue import create_queue_client, enqueue_job
from .jobs.redis_store import (
    create_job,
    create_job_store,
    expire_job_response,
    failed_job_response,
    job_status_response,
    mark_failed,
)
from .jobs.schemas import CreateJobRequest, CreateJobResponse, JobStatusResponse
from .model.catalog import get_model_output_fields
from .storage.s3 import create_blob_store

load_dotenv()

settings = get_settings()
model_output_fields = get_model_output_fields(settings.model_name)
queue_client = create_queue_client(settings.redis_url)
job_store = create_job_store(
    settings.redis_url,
    prefix=settings.redis_key_prefix,
    ttl_seconds=settings.job_ttl_seconds,
)
blob_store = create_blob_store(settings)
blob_store.ensure_bucket()

app = FastAPI()
router = APIRouter()


def _normalized_prefix() -> str:
    if not settings.api_base_path:
        return ""
    return settings.api_base_path if settings.api_base_path.startswith("/") else f"/{settings.api_base_path}"


def _status_url(request: Request, job_id: str) -> str:
    return f"{str(request.base_url).rstrip('/')}{_normalized_prefix()}/jobs/{job_id}"


@router.get("/info")
def info():
    return {
        "data": {
            "model": settings.model_name,
            "role": settings.app_role,
            "output_fields": model_output_fields,
        }
    }


@router.post("/jobs", status_code=status.HTTP_202_ACCEPTED, response_model=CreateJobResponse)
def create_model_job(body: CreateJobRequest, request: Request):
    fields = body.fields or model_output_fields
    job_id = str(uuid4())
    result_object_key = blob_store.make_result_key(settings.model_name, job_id)
    result_put_url = blob_store.generate_put_url(
        result_object_key,
        expires_seconds=settings.result_put_url_ttl_seconds,
    )

    job = create_job(
        job_store,
        job_id=job_id,
        model=settings.model_name,
        get_url=body.get_url,
        fields=fields,
        result_object_key=result_object_key,
        result_put_url=result_put_url,
        webhook=body.webhook.model_dump(mode="json") if body.webhook else None,
    )
    enqueue_job(queue_client, settings.redis_key_prefix, settings.model_name, job["job_id"])

    return CreateJobResponse(
        job_id=job["job_id"],
        model=settings.model_name,
        status=job["status"],
        created_at=job["created_at"],
        status_url=_status_url(request, job["job_id"]),
    )


@router.get("/jobs/{job_id}", response_model=JobStatusResponse)
def get_model_job_status(job_id: str):
    job = job_store.get_job(job_id)
    if job is None:
        return expire_job_response(job_id, settings.model_name)

    if job["status"] == "succeeded":
        if not blob_store.head_object(job["result_object_key"]):
            job = mark_failed(job_store, job_id, "Result object is missing from object storage.")
            return failed_job_response(job)

        result_get_url, expires_at = blob_store.generate_get_url(
            job["result_object_key"],
            expires_seconds=settings.result_get_url_ttl_seconds,
        )
        return job_status_response(job, result_get_url=result_get_url, result_url_expires_at=expires_at)

    return job_status_response(job)


@app.exception_handler(ValueError)
def handle_value_error(_: Request, exc: ValueError) -> JSONResponse:
    return JSONResponse(status_code=400, content={"error": str(exc)})


if settings.api_base_path:
    app.include_router(router, prefix=_normalized_prefix())
else:
    app.include_router(router)
