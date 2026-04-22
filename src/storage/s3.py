from __future__ import annotations

from datetime import UTC, datetime, timedelta
import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

from ..config import Settings
from .blob_store import BlobStore


class S3BlobStore(BlobStore):
    def __init__(self, settings: Settings):
        self.bucket = settings.object_storage_bucket
        self.region = settings.object_storage_region
        self.internal_client = self._build_client(
            settings.object_storage_internal_endpoint,
            settings,
        )
        self.public_client = self._build_client(
            settings.object_storage_public_endpoint,
            settings,
        )

    @staticmethod
    def _build_client(endpoint_url: str, settings: Settings):
        session = boto3.session.Session()
        return session.client(
            "s3",
            region_name=settings.object_storage_region,
            endpoint_url=endpoint_url,
            aws_access_key_id=settings.object_storage_access_key,
            aws_secret_access_key=settings.object_storage_secret_key,
            use_ssl=settings.object_storage_secure,
            config=Config(
                signature_version="s3v4",
                s3={"addressing_style": "path" if settings.object_storage_force_path_style else "auto"},
            ),
        )

    def ensure_bucket(self) -> None:
        try:
            self.internal_client.head_bucket(Bucket=self.bucket)
        except ClientError:
            self.internal_client.create_bucket(Bucket=self.bucket)

    def make_result_key(self, model: str, job_id: str) -> str:
        return f"results/{model}/{job_id}.json"

    def generate_put_url(self, object_key: str, *, expires_seconds: int) -> str:
        return self.internal_client.generate_presigned_url(
            "put_object",
            Params={
                "Bucket": self.bucket,
                "Key": object_key,
                "ContentType": "application/json",
            },
            ExpiresIn=expires_seconds,
        )

    def generate_get_url(self, object_key: str, *, expires_seconds: int) -> tuple[str, str]:
        url = self.public_client.generate_presigned_url(
            "get_object",
            Params={"Bucket": self.bucket, "Key": object_key},
            ExpiresIn=expires_seconds,
        )
        expires_at = (
            datetime.now(UTC).replace(microsecond=0) + timedelta(seconds=expires_seconds)
        ).isoformat().replace("+00:00", "Z")
        return url, expires_at

    def head_object(self, object_key: str) -> bool:
        try:
            self.internal_client.head_object(Bucket=self.bucket, Key=object_key)
            return True
        except ClientError:
            return False


def create_blob_store(settings: Settings) -> S3BlobStore:
    return S3BlobStore(settings)
