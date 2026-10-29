"""
Real ML prediction endpoints for SuriStanya.
"""
from flask import Blueprint, request, jsonify
from utils.model_loader import get_models, get_health_status
from utils.preprocessing import (
    load_image_from_bytes,
    extract_features,
    predict_probabilities,
)
from utils.fusion import build_fusion_vector, run_fusion
from utils.response_builder import build_api_response

predict_bp = Blueprint("predict", __name__)
REQUIRED_MODALITIES = ["tongue", "palm", "nail", "eye"]

def _run_modality(modality: str, image_bytes: bytes) -> dict:
    m = get_models().get(modality)
    if m is None:
        raise RuntimeError(f"Model for '{modality}' is not loaded.")

    img = load_image_from_bytes(image_bytes)
    features = extract_features(m["feature_model"], img)
    scaled = m["scaler"].transform(features)
    probs = predict_probabilities(m["classifier"], scaled)

    p_anemic = float(probs[1])
    threshold = float(m["threshold"])
    low_confidence = abs(p_anemic - threshold) < 0.15
    label = "Anemic" if p_anemic >= threshold else "Non-Anemic"
    confidence = p_anemic if label == "Anemic" else (1.0 - p_anemic)

    return {
        "modality": modality,
        "label": label,
        "confidence": confidence,
        "probabilities": [float(p) for p in probs],
        "threshold": threshold,
        "low_confidence": low_confidence,
    }

@predict_bp.route("/health", methods=["GET"])
def predict_health():
    return jsonify({
        "status": "ok",
        "models_loaded": get_health_status(),
    })

@predict_bp.route("/", methods=["POST"])
def predict_all():
    received = [k for k in REQUIRED_MODALITIES if k in request.files]
    if len(received) != len(REQUIRED_MODALITIES):
        missing = [k for k in REQUIRED_MODALITIES if k not in request.files]
        return jsonify({
            "error": "Missing images",
            "received": received,
            "missing": missing,
            "required": REQUIRED_MODALITIES,
        }), 400

    modality_results: dict = {}
    try:
        for modality in REQUIRED_MODALITIES:
            file = request.files[modality]
            if not file or file.filename == "":
                return jsonify({"error": f"Empty file for '{modality}'"}), 400
            modality_results[modality] = _run_modality(modality, file.read())
    except Exception as exc:
        return jsonify({"error": f"Prediction failed: {exc}"}), 500

    fusion_model = get_models().get("fusion")
    if fusion_model is None:
        return jsonify({"error": "Fusion model not loaded."}), 500

    fusion_vector = build_fusion_vector(modality_results)
    fusion_result = run_fusion(fusion_model, fusion_vector)

    # 1. Bundle the raw probabilities
    raw_probs = {
        'modalities': {m: r['probabilities'] for m, r in modality_results.items()},
        'fusion': fusion_result['probabilities'],
    }

    # 2. Build normal response
    response = build_api_response(modality_results, fusion_result)
    
    # 3. Attach the new fields
    response['raw_probs'] = raw_probs
    response['model_version'] = "v1.0-79.4"
    
    return jsonify(response)

@predict_bp.route("/<modality>", methods=["POST"])
def predict_single(modality: str):
    if modality not in REQUIRED_MODALITIES:
        return jsonify({"error": f"Unknown modality: {modality}"}), 400
    if "image" not in request.files:
        return jsonify({"error": "No image file."}), 400
    file = request.files["image"]
    if not file or file.filename == "":
        return jsonify({"error": "Empty file."}), 400
    try:
        result = _run_modality(modality, file.read())
        result["disclaimer"] = "This is a screening tool only. Not a medical diagnosis."
        return jsonify(result)
    except Exception as exc:
        return jsonify({"error": f"Prediction failed: {exc}"}), 500