from .model import ModelWrapper
from fastapi import FastAPI, Response, Query
from dotenv import load_dotenv
from .lib.validator import PredictBody
import importlib
import os

load_dotenv()

MODEL_NAME = os.environ.get("MODEL_NAME")

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

@app.get("/info")
def info():
    return {"data": str(model)}

@app.post("/predict")
def predict(body: PredictBody, response: Response, fields: str = Query(",".join(model.output_fields))):
    try:
        result = model.predict(body.input, fields.split(','))
        if result["error"]:
            response.status_code = result["error"]["status_code"]
        return {"data": result["data"], "error": result["error"]} 
    except Exception as e:
        response.status_code = 500
        return {"error": str(e), "data": None}   