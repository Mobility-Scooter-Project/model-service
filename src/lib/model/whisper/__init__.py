from .. import ModelWrapper, ModelResult
from faster_whisper import WhisperModel, BatchedInferencePipeline
import requests
import os
from datetime import datetime

model_size = "small"

class whisper(ModelWrapper):
    def __init__(self):
        super().__init__("whisper", batch_size=16, output_fields=[])
        self.model = None
        
    def load_model(self):
        self.base_model = WhisperModel(model_size, device=self.device, compute_type="float32")
        self.model = BatchedInferencePipeline(self.base_model)
        
    def predict(self, input, fields = []):
        if not self.model:
            raise ValueError("Model not loaded. Call load_model() before predict().")
        
        res = ModelResult(data=None, error=None)
        # download the input file
        filename = f"{datetime.now().strftime('%Y%m%d%H%M%S')}.mp3"
        local_path = f"/tmp/whisper/{filename}"
        os.makedirs(os.path.dirname(local_path), exist_ok=True)
        self._download_input_file(input, local_path)
        self._download_input_file(input, local_path)
        
        try:
            segments, info = self.model.transcribe(local_path, batch_size=self.batch_size)
            res["data"] = []
            
            for segment in segments:
                res["data"].append({
                    "id": segment.id,
                    "seek": segment.seek,
                    "start": segment.start,
                    "end": segment.end,
                    "text": segment.text,
                    "tokens": segment.tokens,
                    "avg_logprob": segment.avg_logprob,
                    "compression_ratio": segment.compression_ratio,
                    "no_speech_prob": segment.no_speech_prob
                })
                
        except Exception as e:
            res["error"] = {"message": str(e), "status_code": 500}
        finally:
            return res
        
    def _download_input_file(self, url: str, dest_path: str) -> None:
        try:
            response = requests.get(url, stream=True)
            response.raise_for_status()
            with open(dest_path, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    f.write(chunk)
        except Exception as e:
            raise RuntimeError(f"Failed to download file from {url}: {e}")