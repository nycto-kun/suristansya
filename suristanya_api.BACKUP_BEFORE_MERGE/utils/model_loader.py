"""
Loads all 4 modality models (frozen CNN + classifier + scaler + threshold)
and the fusion model ONCE at Flask startup.

Called from app.py at import time so gunicorn workers reuse the
same in-memory models for every request.
"""
import os
import pickle
from tensorflow.keras.models import load_model

import warnings
import xgboost as xgb
xgb.set_config(verbosity=0)
warnings.filterwarnings("ignore", category=UserWarning, module="xgboost")

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS_DIR = os.path.join(BASE_DIR, "models")
MODALITIES = ["tongue", "eye", "nail", "palm"]

# Global registry: {"tongue": {...}, "eye": {...}, ..., "fusion": model}
MODELS: dict = {}


def _load_pickle(path: str):
    """
    Try loading with pickle first, then joblib.
    Some .pkl files are actually joblib-serialized (different binary format).
    """
    # Attempt 1: standard pickle
    try:
        with open(path, "rb") as f:
            return pickle.load(f)
    except Exception:
        pass

    # Attempt 2: joblib
    try:
        import joblib
        return joblib.load(path)
    except Exception as e:
        raise RuntimeError(
            f"Could not load {path} with pickle OR joblib. "
            f"Last error: {type(e).__name__}: {e}"
        )


def load_all_models() -> None:
    """Populate the global MODELS dict. Called once at app startup."""
    for modality in MODALITIES:
        try:
            feature_model = load_model(
                os.path.join(MODELS_DIR, f"{modality}_feature_model.h5"),
                compile=False,
            )
            classifier = _load_pickle(
                os.path.join(MODELS_DIR, f"{modality}_classifier.pkl")
            )
            scaler = _load_pickle(
                os.path.join(MODELS_DIR, f"{modality}_scaler.pkl")
            )
            threshold_data = _load_pickle(
                os.path.join(MODELS_DIR, f"{modality}_threshold.pkl")
            )
            if isinstance(threshold_data, dict):
                threshold = float(threshold_data.get("threshold", 0.5))
            else:
                threshold = float(threshold_data)

            MODELS[modality] = {
                "feature_model": feature_model,
                "classifier": classifier,
                "scaler": scaler,
                "threshold": threshold,
            }
            print(f"[startup] Loaded {modality} (threshold={threshold})")

        except Exception as exc:
            print(f"[startup] FAILED to load {modality}: {exc}")
            MODELS[modality] = None

    # Fusion model
    try:
        MODELS["fusion"] = _load_pickle(
            os.path.join(MODELS_DIR, "fusion_model.pkl")
        )
        MODELS["fusion_metadata"] = _load_pickle(
            os.path.join(MODELS_DIR, "fusion_metadata.pkl")
        )
        print("[startup] Loaded fusion model + metadata")
    except Exception as exc:
        print(f"[startup] FAILED to load fusion model: {exc}")
        MODELS["fusion"] = None
        MODELS["fusion_metadata"] = None


def get_models() -> dict:
    return MODELS


def get_health_status() -> dict:
    """Used by /health to report which models are loaded."""
    status = {m: MODELS.get(m) is not None for m in MODALITIES}
    status["fusion"] = MODELS.get("fusion") is not None
    return status