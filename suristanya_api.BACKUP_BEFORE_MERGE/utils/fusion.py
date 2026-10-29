"""
Fusion logic.

Concatenates 4 probability vectors (2 classes x 4 modalities = 8-dim)
in the modality order the fusion model was trained with.

If `fusion_metadata.pkl` exposes an ordering key (e.g. "modalities",
"feature_order", or "order"), we use it. Otherwise we default to
["tongue", "eye", "nail", "palm"].
"""
import numpy as np

DEFAULT_ORDER = ["tongue", "eye", "nail", "palm"]


def get_modality_order() -> list:
    from utils.model_loader import get_models
    meta = get_models().get("fusion_metadata")
    if isinstance(meta, dict):
        for key in ("modalities", "feature_order", "order", "modality_order"):
            val = meta.get(key)
            if isinstance(val, (list, tuple)) and len(val) == 4:
                return list(val)
    return DEFAULT_ORDER


def build_fusion_vector(modality_results: dict) -> np.ndarray:
    """Build the 8-dim input vector for the fusion model."""
    order = get_modality_order()
    vector = []
    for modality in order:
        result = modality_results.get(modality)
        probs = result["probabilities"] if result else [0.5, 0.5]
        vector.extend(float(p) for p in probs)
    return np.array([vector], dtype=np.float32)


def run_fusion(fusion_model, fusion_vector: np.ndarray) -> dict:
    """Return {label, confidence, probabilities} from the fusion model."""
    if hasattr(fusion_model, "predict_proba"):
        probs = np.asarray(fusion_model.predict_proba(fusion_vector))[0]
    else:
        probs = np.asarray(fusion_model.predict(fusion_vector)).flatten()
    if probs.size == 1:
        p = float(probs[0])
        probs = np.array([1.0 - p, p], dtype=np.float64)

    idx = int(np.argmax(probs))
    return {
        "label": "Anemic" if idx == 1 else "Non-Anemic",
        "confidence": float(probs[idx]),
        "probabilities": [float(p) for p in probs],
    }