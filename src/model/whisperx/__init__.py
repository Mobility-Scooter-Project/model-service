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

import os
import gc
import torch
import whisperx as whisperx_lib
import contextlib
from datetime import datetime
from collections import defaultdict

from .. import ModelWrapper, ModelResult, ModelError
from ...utils.remote import download_file


def _env_flag(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.lower() in {"1", "true", "yes", "on"}


class whisperx(ModelWrapper):
    def __init__(self):
        default_batch_size = 16 if torch.cuda.is_available() else 4
        super().__init__(
            "whisperx",
            batch_size=int(os.getenv("WHISPERX_BATCH_SIZE", str(default_batch_size))),
            output_fields=["transcript"],
        )
        self.whisper_model = None
        self.diarize_model = None
        
        # Configurations
        self.model_size = os.getenv("WHISPERX_SIZE", "base" if self.device == "cuda" else "tiny")
        self.hf_token = os.getenv("HF_TOKEN")
        self.compute_type = os.getenv("COMPUTE_TYPE", "float16" if self.device == "cuda" else "int8")
        self.enable_diarization = _env_flag("WHISPERX_ENABLE_DIARIZATION", self.device == "cuda")
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

            if self.enable_diarization:
                if not self.hf_token:
                    raise ValueError("HF_TOKEN environment variable is required when diarization is enabled.")

                from whisperx.diarize import DiarizationPipeline

                self.diarize_model = DiarizationPipeline(
                    token=self.hf_token,
                    device=self.device,
                )

    def predict(self, input, fields=["transcript"]):
        if not self.whisper_model:
            raise ValueError("Model not loaded. Call load_model() before predict().")

        res = ModelResult(data=None, error=None, metadata={"device": self.device})
        filename = f"{datetime.now().strftime('%Y%m%d%H%M%S')}"
        local_path = "/tmp/whisperx"
        file_path = ""

        try:
            file_path = download_file(input, local_path, filename)
            
            audio = whisperx_lib.load_audio(file_path)
            result = self.whisper_model.transcribe(audio, batch_size=self.batch_size)

            model_a, metadata = whisperx_lib.load_align_model(language_code=result["language"], device=self.device)
            result = whisperx_lib.align(result["segments"], model_a, metadata, audio, self.device, return_char_alignments=False)
            del model_a
            gc.collect()
            if self.device == "cuda":
                torch.cuda.empty_cache()

            if self.enable_diarization and self.diarize_model:
                diarize_segments = self.diarize_model(audio, min_speakers=1, max_speakers=2)
                result = whisperx_lib.assign_word_speakers(diarize_segments, result)

            res["data"] = self._format_transcript(result)

        except Exception as e:
            res["error"] = ModelError(message=str(e), status_code=500)
        finally:
            if os.path.exists(file_path):
                os.remove(file_path)
            return res

    def _format_transcript(self, result):
        if not any("speaker" in segment for segment in result["segments"]):
            return [
                {
                    "speaker": None,
                    "start": segment["start"],
                    "end": segment["end"],
                    "text": segment["text"].strip(),
                }
                for segment in result["segments"]
            ]

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
