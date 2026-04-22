from abc import ABC, abstractmethod
import importlib
from typing import TypedDict, Dict, List
import torch

class ModelError(TypedDict):
    message: str
    status_code: int

class ModelResult(TypedDict):
    data: List | None
    error: ModelError | None
    metadata: Dict | None

class ModelWrapper(ABC):
    def __init__(self, model_name, batch_size=32, output_fields = []):
        self.model_name = model_name
        self.output_fields = output_fields
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        self.batch_size = batch_size
        
    @abstractmethod
    def load_model(self):
        pass
    
    @abstractmethod
    def predict(self, input, fields: List = []) -> ModelResult:
        pass
    
    def __str__(self):
        return f"Model Name: {self.model_name} Output Fields: {self.output_fields}"


def create_model(model_name: str) -> "ModelWrapper":
    try:
        module = importlib.import_module(f".{model_name}", package="src.model")
        return getattr(module, model_name)()
    except ModuleNotFoundError as exc:
        raise ValueError(f"model {model_name} not found: {exc}") from exc
    except AttributeError as exc:
        raise ValueError(f"model class {model_name} not found or failed to load: {exc}") from exc
