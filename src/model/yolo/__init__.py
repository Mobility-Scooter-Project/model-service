import os

from .. import ModelWrapper, ModelResult, ModelError
from ultralytics import YOLO

class yolo(ModelWrapper):
    """Pose-detection model packaged as a standalone GHCR image."""

    def __init__(self):
        model_cache_dir = os.getenv("MODEL_CACHE_DIR", "/app/.cache")
        model_filename = os.getenv("YOLO_MODEL_FILENAME", "yolo11n-pose.pt")
        super().__init__(os.path.join(model_cache_dir, model_filename), output_fields=["boxes", "keypoints", "masks", "names"])

    def load_model(self):
        os.makedirs(os.path.dirname(self.model_name), exist_ok=True)
        self.model = YOLO(self.model_name).to(self.device)

    def predict(self, input, fields = ["boxes","keypoints","masks","names"]):
        if self.model is None:
            raise ValueError("Model not loaded. Call load_model() before predict().")
        
        res = ModelResult(data=None, error=None, metadata={"device": self.device})
        
        try:
            outputs = self.model(input)
            res["data"] = []
            
            for output in outputs:
                result = {}
                if "boxes" in fields:
                    result["boxes"] = []
                    for box in output.boxes:
                        result["boxes"].append(
                            {
                               "data": box.data.tolist() 
                            }
                            )
                if "keypoints" in fields:
                    result["keypoints"] = output.keypoints.data.tolist()
                if "masks" in fields:
                    result["masks"] = output.masks
                if "names" in fields:
                    result["names"] = output.names
                
                res["data"].append(result)
                
        except Exception as e:
            res["error"] = ModelError(message=str(e), status_code=500)
        finally:
            return res
