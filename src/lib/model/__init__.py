from abc import ABC, abstractmethod
from typing import TypedDict, Dict, List, Any

class ModelError(TypedDict):
    message: str
    status_code: int

class ModelResult(TypedDict):
    data: List | None
    error: ModelError | None

class ModelWrapper(ABC):
    def __init__(self, model_name, output_fields = []):
        self.model_name = model_name
        self.output_fields = output_fields
        
    @abstractmethod
    def load_model(self):
        pass
    
    @abstractmethod
    def predict(self, input, fields: List = []) -> ModelResult:
        pass
    
    def __str__(self):
        return f"Model Name: {self.model_name} Output Fields: {self.output_fields}"