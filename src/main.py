from .lib.model import ModelWrapper
from fastapi import FastAPI, Response, Query
from dotenv import load_dotenv
from .lib.validator import PredictBody
import importlib
import os

load_dotenv()

MODEL_NAME = os.environ.get("MODEL_NAME")

if not MODEL_NAME:
    raise ValueError("missing MODEL_NAME")

try:
    module = importlib.import_module(f".lib.model.{MODEL_NAME}", package="src")   
    model: ModelWrapper = getattr(module, MODEL_NAME)() 
except ModuleNotFoundError:
    raise ValueError(f"model {MODEL_NAME} not found")

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