from enum import Enum

from pydantic import BaseModel


class JobState(str, Enum):
    queued = "queued"
    running = "running"
    succeeded = "succeeded"
    failed = "failed"
    expired = "expired"


class WebhookConfig(BaseModel):
    url: str
    secret: str | None = None


class CreateJobRequest(BaseModel):
    get_url: str
    fields: list[str] | None = None
    webhook: WebhookConfig | None = None


class CreateJobResponse(BaseModel):
    job_id: str
    model: str
    status: JobState
    created_at: str
    status_url: str


class JobError(BaseModel):
    message: str
    status_code: int = 500


class WebhookDeliveryStatus(BaseModel):
    attempted_at: str | None = None
    success: bool | None = None
    status_code: int | None = None
    error: str | None = None


class JobStatusResponse(BaseModel):
    job_id: str
    model: str
    status: JobState
    created_at: str | None = None
    started_at: str | None = None
    finished_at: str | None = None
    attempts: int = 0
    result_get_url: str | None = None
    expires_at: str | None = None
    error: JobError | None = None
    webhook: WebhookDeliveryStatus | None = None
