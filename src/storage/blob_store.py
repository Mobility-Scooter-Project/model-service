from __future__ import annotations

from datetime import datetime
from typing import Protocol


class BlobStore(Protocol):
    bucket: str

    def ensure_bucket(self) -> None:
        ...

    def make_result_key(self, model: str, job_id: str) -> str:
        ...

    def generate_put_url(self, object_key: str, *, expires_seconds: int) -> str:
        ...

    def generate_get_url(self, object_key: str, *, expires_seconds: int) -> tuple[str, str]:
        ...

    def head_object(self, object_key: str) -> bool:
        ...
