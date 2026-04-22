MODEL_OUTPUT_FIELDS: dict[str, list[str]] = {
    "yolo": ["boxes", "keypoints", "masks", "names"],
    "whisperx": ["transcript"],
}


def get_model_output_fields(model_name: str) -> list[str]:
    try:
        return MODEL_OUTPUT_FIELDS[model_name]
    except KeyError as exc:
        raise ValueError(f"model metadata for {model_name} not found") from exc
