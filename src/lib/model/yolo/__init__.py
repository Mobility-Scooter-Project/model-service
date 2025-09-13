from .. import ModelWrapper, ModelResult, ModelError
from ultralytics import YOLO

class yolo(ModelWrapper):
    def __init__(self):
        super().__init__("models/yolo11n-pose.pt", ["boxes", "keypoints", "masks", "names"])

    def load_model(self):
        self.model = YOLO(self.model_name)

    def predict(self, input, fields = ["boxes","keypoints","masks","names"]):
        if self.model is None:
            raise ValueError("Model not loaded. Call load_model() before predict().")
        
        res = ModelResult(data=None, error=None)
        
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
                print(output.boxes)
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