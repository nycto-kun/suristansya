"""
Image preprocessing + feature extraction + classifier inference.

Pipeline (as specified):
    bytes -> RGB -> resize 224x224 -> normalize [0,1]
          -> frozen CNN -> flatten -> scaler -> classifier -> probabilities
"""
import io
import numpy as np
import cv2
from PIL import Image

TARGET_SIZE = (224, 224)


def load_image_from_bytes(image_bytes: bytes) -> np.ndarray:
    """Decode bytes -> RGB float32 array (224, 224, 3) in [0, 1]."""
    try:
        pil = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        arr = np.array(pil, dtype=np.float32)
        arr = cv2.resize(arr, TARGET_SIZE)
        return arr / 255.0
    except Exception as exc:
        raise ValueError(f"Invalid or corrupted image: {exc}")


def extract_features(feature_model, img_array: np.ndarray) -> np.ndarray:
    """
    Run frozen CNN and reduce to a 1-D feature vector.

    Frozen CNNs sometimes output 4-D (batch, H, W, C) spatial feature maps.
    We apply Global Average Pooling (mean over H, W) to match the
    training pipeline, which used pooled features (e.g. 2048 for ResNet50,
    1280 for EfficientNetB0).
    """
    batch = np.expand_dims(img_array, axis=0)
    features = feature_model.predict(batch, verbose=0)

    # Debug — comment out once things work
    print(f"[extract_features] raw output shape = {features.shape}")

    # If output has spatial dims (4D), pool them away
    if features.ndim == 4:
        # Global Average Pooling: mean over H and W
        features = np.mean(features, axis=(1, 2))
        print(f"[extract_features] after GAP shape = {features.shape}")

    # Flatten to (1, D)
    features = features.reshape(1, -1)
    print(f"[extract_features] final shape = {features.shape}")

    return features


def predict_probabilities(classifier, scaled_features: np.ndarray) -> np.ndarray:
    """Return [P(Non-Anemic), P(Anemic)] as a float array of length 2."""
    if hasattr(classifier, "predict_proba"):
        probs = np.asarray(classifier.predict_proba(scaled_features))[0]
    else:
        probs = np.asarray(classifier.predict(scaled_features)).flatten()
        if probs.size == 1:
            p = float(probs[0])
            probs = np.array([1.0 - p, p], dtype=np.float64)
    if probs.size == 1:
        p = float(probs[0])
        probs = np.array([1.0 - p, p], dtype=np.float64)
    return probs.astype(np.float64)