from .model import ModelWrapper
from fastapi import APIRouter, FastAPI, Query, Response
from dotenv import load_dotenv
from .lib.validator import PredictBody
import importlib
import os

load_dotenv()

MODEL_NAME = os.environ.get("MODEL_NAME")
API_BASE_PATH = os.environ.get("API_BASE_PATH", "").strip().rstrip("/")

if not MODEL_NAME:
    raise ValueError("missing MODEL_NAME")

def load_model_class(model_name: str):
    """
    Load model class from flat structure: src.lib.model.model_name
    """
    try:
        module = importlib.import_module(f".model.{model_name}", package="src")
        return getattr(module, model_name)()
    except ModuleNotFoundError as e:
        raise ValueError(f"model {model_name} not found: {e}")
    except AttributeError as e:
        raise ValueError(f"model class {model_name} not found or failed to load: {e}")

try:
    model: ModelWrapper = load_model_class(MODEL_NAME)
except ValueError as e:
    raise e

try:
    model.load_model()
except Exception as e:
    raise RuntimeError(f"failed to load model {MODEL_NAME}: {e}")    

app = FastAPI()
router = APIRouter()

def parse_fields(fields: str):
    requested_fields = [field.strip() for field in fields.split(",") if field.strip()]
    return requested_fields or model.output_fields

@router.get("/info")
def info():
    return {"data": str(model)}

@router.post("/predict")
def predict(body: PredictBody, response: Response, fields: str = Query(",".join(model.output_fields))):
    result = model.predict(body.input, parse_fields(fields))

    if result.get("error"):
        response.status_code = result["error"].get("status_code", 500)

    return result

# Keep the bare routes for the existing docker-compose/nginx workflow, where the
# reverse proxy strips `/api/v1/<model>` before the request reaches the app.
app.include_router(router)

# Stage 3 ingress forwards the original `/api/v1/<model>/...` path through the
# KEDA interceptor, so the service must also accept that prefixed route shape.
if API_BASE_PATH:
    normalized_prefix = API_BASE_PATH if API_BASE_PATH.startswith("/") else f"/{API_BASE_PATH}"
    app.include_router(router, prefix=normalized_prefix)
