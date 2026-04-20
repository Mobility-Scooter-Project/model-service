from .model import ModelWrapper
from fastapi import FastAPI, Response, Query, BackgroundTasks
from dotenv import load_dotenv
from .lib.validator import PredictBody
import importlib
import os
import threading
import uuid

load_dotenv()

MODEL_NAME = os.environ.get("MODEL_NAME")
MODEL_EAGER_LOAD = os.environ.get("MODEL_EAGER_LOAD", "").lower() in {"1", "true", "yes", "on"}

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

_model_load_lock = threading.Lock()


def _is_model_loaded() -> bool:
    return getattr(model, "_loaded", False)


def ensure_model_loaded() -> None:
    if _is_model_loaded():
        return

    with _model_load_lock:
        if _is_model_loaded():
            return

        try:
            model.load_model()
        except Exception as e:
            raise RuntimeError(f"failed to load model {MODEL_NAME}: {e}") from e

        setattr(model, "_loaded", True)


if MODEL_EAGER_LOAD:
    ensure_model_loaded()

app = FastAPI()

jobs = {}

def process_prediction(job_id: str, input_data, fields: list):
    try:
        ensure_model_loaded()
        result = model.predict(input_data, fields)
        jobs[job_id] = {
            "status": "completed" if not result.get("error") else "failed",
            "data": result.get("data"),
            "error": result.get("error"),
            "metadata": result.get("metadata")
        }
    except Exception as e:
        jobs[job_id] = {
            "status": "failed",
            "error": {"message": str(e), "status_code": 500},
            "data": None,
            "metadata": None
        }

@app.get("/info")
def info():
    return {"data": str(model), "loaded": _is_model_loaded()}

@app.post("/predict")
def predict(body: PredictBody, background_tasks: BackgroundTasks, fields: str = Query(",".join(model.output_fields))):
    job_id = str(uuid.uuid4())
    jobs[job_id] = {"status": "processing"}
    
    background_tasks.add_task(process_prediction, job_id, body.input, fields.split(','))
    
    return {"job_id": job_id, "status": "processing"}

@app.get("/status/{job_id}")
def get_status(job_id: str, response: Response):
    job = jobs.get(job_id)
    if not job:
        response.status_code = 404
        return {"error": {"message": "Job not found", "status_code": 404}, "status": "not_found"}
    
    if job.get("error"):
        response.status_code = job["error"].get("status_code", 500)
        
    return job
