import logging
import warnings

# Suppress noisy Pyannote/Torchcodec warnings
def _setup_warnings():
    noisy_libraries = [
        "pyannote", "speechbrain", "whisperx",
        "pytorch_lightning", "torch", "torchaudio",
        "torchcodec",
    ]
    for lib in noisy_libraries:
        warnings.filterwarnings("ignore", module=rf"^{lib}(\.|$)")
        lib_logger = logging.getLogger(lib) 
        lib_logger.setLevel(logging.ERROR)
        lib_logger.propagate = False

_setup_warnings()
logger = logging.getLogger(__name__)

import os
import gc
import torch
import whisperx as whisperx_lib
import contextlib
from datetime import datetime
from collections import defaultdict

from .. import ModelWrapper, ModelResult, ModelError
from ...utils.remote import download_file

class whisperx(ModelWrapper):
    """Diarized transcription model packaged as a standalone GHCR image."""

    def __init__(self):
        super().__init__("whisperx", batch_size=16, output_fields=["transcript"])
        self.whisper_model = None
        self.diarize_model = None
        
        # Configurations
        self.model_size = os.getenv("WHISPERX_SIZE", "base")
        self.hf_token = os.getenv("HF_TOKEN")
        self.compute_type = os.getenv("COMPUTE_TYPE", "float16" if self.device == "cuda" else "int8")
        self.batch_size = int(os.getenv("WHISPERX_BATCH_SIZE", str(self.batch_size)))
        self.vad_onset = float(os.getenv("VAD_ONSET", "0.500"))
        self.vad_offset = float(os.getenv("VAD_OFFSET", "0.363"))

    @staticmethod
    @contextlib.contextmanager
    def _unsafe_torch_load():
        original_load = torch.load
        def patched_load(*args, **kwargs):
            kwargs.setdefault("weights_only", False)
            return original_load(*args, **kwargs)
        torch.load = patched_load
        orig_matmul = torch.backends.cuda.matmul.allow_tf32
        orig_cudnn = torch.backends.cudnn.allow_tf32
        torch.backends.cuda.matmul.allow_tf32 = True
        torch.backends.cudnn.allow_tf32 = True
        try:
            yield
        finally:
            torch.load = original_load
            torch.backends.cuda.matmul.allow_tf32 = orig_matmul
            torch.backends.cudnn.allow_tf32 = orig_cudnn

    def load_model(self):
        if not self.hf_token:
            raise ValueError("HF_TOKEN environment variable is required for diarization.")

        logger.info(
            "Loading WhisperX model",
            extra={
                "device": self.device,
                "model_size": self.model_size,
                "compute_type": self.compute_type,
                "batch_size": self.batch_size,
            },
        )
        with self._unsafe_torch_load():
            vad_options = {
                "vad_onset": self.vad_onset,
                "vad_offset": self.vad_offset,
            }

            self.whisper_model = whisperx_lib.load_model(
                self.model_size,
                device=self.device,
                compute_type=self.compute_type,
                vad_options=vad_options,
            )
            
            from whisperx.diarize import DiarizationPipeline
            self.diarize_model = DiarizationPipeline(
                token=self.hf_token,
                device=self.device,
            )

    def predict(self, input, fields=["transcript"]):
        if not self.whisper_model or not self.diarize_model:
            raise ValueError("Model not loaded. Call load_model() before predict().")

        res = ModelResult(data=None, error=None, metadata={"device": self.device})
        filename = f"{datetime.now().strftime('%Y%m%d%H%M%S')}"
        local_path = "/tmp/whisperx"
        file_path = ""

        try:
            logger.info("Starting WhisperX request for %s", input)
            file_path = download_file(input, local_path, filename)
            logger.info("Downloaded audio to %s", file_path)

            audio = whisperx_lib.load_audio(file_path)
            logger.info("Decoded audio successfully")

            result = self.whisper_model.transcribe(audio, batch_size=self.batch_size)
            logger.info("Transcription complete")

            model_a, metadata = whisperx_lib.load_align_model(language_code=result["language"], device=self.device)
            logger.info("Alignment model loaded for language %s", result["language"])
            result = whisperx_lib.align(result["segments"], model_a, metadata, audio, self.device, return_char_alignments=False)
            logger.info("Alignment complete")
            del model_a
            gc.collect()
            torch.cuda.empty_cache()

            diarize_segments = self.diarize_model(audio, min_speakers=1, max_speakers=2)
            logger.info("Diarization complete")
            result = whisperx_lib.assign_word_speakers(diarize_segments, result)
            logger.info("Speaker assignment complete")

            res["data"] = self._format_transcript(result)
            logger.info("Formatted WhisperX transcript with %d segments", len(res["data"]))

        except Exception as e:
            logger.exception("WhisperX prediction failed")
            res["error"] = ModelError(message=str(e), status_code=500)
        finally:
            if os.path.exists(file_path):
                os.remove(file_path)
            return res

    def _format_transcript(self, result):
        speakerScript = defaultdict(list)
        speakerLabel = defaultdict(str)
        
        for segment in result["segments"]:
            if "speaker" not in segment:
                continue
            start, end = segment["start"], segment["end"]
            speaker, sentence = segment["speaker"], segment["text"]
            speakerScript[speaker].append([start, end, sentence])

        if len(speakerScript["SPEAKER_00"]) >= len(speakerScript["SPEAKER_01"]):
            speakerLabel["SPEAKER_00"] = "instructor"
            speakerLabel["SPEAKER_01"] = "participant"
        else:
            speakerLabel["SPEAKER_01"] = "instructor"
            speakerLabel["SPEAKER_00"] = "participant"

        scripts = []
        for segment in result["segments"]:
            if "speaker" not in segment:
                continue
            start, end = segment["start"], segment["end"]
            speaker = speakerLabel[segment["speaker"]]
            text = segment["text"].strip()
            
            scripts.append({
                "speaker": speaker,
                "start": start,
                "end": end,
                "text": text
            })

        return scripts
