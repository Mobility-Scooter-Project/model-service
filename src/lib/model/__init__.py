from abc import ABC, abstractmethod
from typing import TypedDict, Dict, List, Any
import os

class ModelError(TypedDict):
    message: str
    status_code: int

class ModelResult(TypedDict):
    data: List | None
    error: ModelError | None

class BaseModelWrapper(ABC):
    """Base model wrapper for all runtimes"""
    def __init__(self, model_name, batch_size=32, output_fields = []):
        self.model_name = model_name
        self.output_fields = output_fields
        self.batch_size = batch_size
        self.runtime = self._detect_runtime()
        
    def _detect_runtime(self) -> str:
        """Detect runtime from environment or default"""
        return os.environ.get("RUNTIME", "pytorch")
        
    @abstractmethod
    def load_model(self):
        pass
    
    @abstractmethod
    def predict(self, input, fields: List = []) -> ModelResult:
        pass
    
    def __str__(self):
        return f"Model Name: {self.model_name} Runtime: {self.runtime} Output Fields: {self.output_fields}"

class ModelWrapper(BaseModelWrapper):
    """PyTorch-specific model wrapper (for backward compatibility)"""
    def __init__(self, model_name, batch_size=32, output_fields = []):
        super().__init__(model_name, batch_size, output_fields)
        # Only import torch if we're actually using PyTorch models
        try:
            import torch
            self.device = "cuda" if torch.cuda.is_available() else "cpu"
        except ImportError:
            self.device = "cpu"

class TensorFlowModelWrapper(BaseModelWrapper):
    """TensorFlow-specific model wrapper"""
    def __init__(self, model_name, batch_size=32, output_fields = []):
        super().__init__(model_name, batch_size, output_fields)
        # Check for GPU availability in TensorFlow
        try:
            import tensorflow as tf
            self.device = "GPU" if len(tf.config.list_physical_devices('GPU')) > 0 else "CPU"
            # Set memory growth to avoid OOM issues
            gpus = tf.config.experimental.list_physical_devices('GPU')
            if gpus:
                try:
                    for gpu in gpus:
                        tf.config.experimental.set_memory_growth(gpu, True)
                except RuntimeError as e:
                    print(f"GPU setup error: {e}")
        except ImportError:
            self.device = "CPU"

class SklearnModelWrapper(BaseModelWrapper):
    """Scikit-learn specific model wrapper"""
    def __init__(self, model_name, batch_size=32, output_fields = []):
        super().__init__(model_name, batch_size, output_fields)
        # Scikit-learn runs on CPU, but we can optimize with joblib
        try:
            import joblib
            # Use all available CPU cores for parallel processing
            self.n_jobs = joblib.cpu_count()
            self.device = f"CPU ({self.n_jobs} cores)"
        except ImportError:
            self.n_jobs = -1
            self.device = "CPU"
    