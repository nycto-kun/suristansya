"""
Convert raw ML results into the JSON shape the SuriStanya Flutter
client expects (summary + predictions[]).

Keeping this contract stable means the frontend needs zero changes.
"""

MODALITY_META = {
    "tongue": {"condition": "Tongue Pallor",         "detected_from": ["Tongue"]},
    "eye":    {"condition": "Eye Conjunctiva Pallor","detected_from": ["Eye"]},
    "nail":   {"condition": "Nail Bed Pallor",       "detected_from": ["Nail"]},
    "palm":   {"condition": "Palm Pallor",           "detected_from": ["Palm"]},
}

ANEMIC_DESCRIPTIONS = {
    "tongue": "Visual markers suggest possible pallor or smoothness on the "
              "tongue — a pattern sometimes associated with iron deficiency.",
    "eye":    "The conjunctiva shows signs of pallor, a common non-invasive "
              "visual indicator used in anemia screening.",
    "nail":   "Nail bed appears pale or lacks the typical pink tone — this "
              "can be linked to low iron over time.",
    "palm":   "Palm creases and color suggest reduced perfusion, which may "
              "indicate anemia.",
}

NON_ANEMIC_DESCRIPTIONS = {
    "tongue": "Tongue surface appears normally colored and textured.",
    "eye":    "Conjunctiva appears pink and well-perfused.",
    "nail":   "Nail bed shows a healthy pink tone.",
    "palm":   "Palm color and creases appear within the normal range.",
}

ANEMIC_RECOMMENDATIONS = {
    "tongue": ["Consider a CBC blood test.",
               "Eat iron-rich foods like liver, spinach, and lentils."],
    "eye":    ["Consider a CBC blood test.",
               "Pair iron-rich foods with vitamin C for better absorption."],
    "nail":   ["Consider a CBC blood test.",
               "Avoid coffee and tea around meals — they block iron uptake."],
    "palm":   ["Consider a CBC blood test.",
               "Stay hydrated and eat balanced, iron-rich meals."],
}

NON_ANEMIC_RECOMMENDATIONS = {
    "tongue": ["Keep hydrated.", "Maintain a balanced diet."],
    "eye":    ["Keep up regular checkups.", "Maintain an iron-rich diet."],
    "nail":   ["Continue routine nail care.", "Stay hydrated."],
    "palm":   ["Maintain a balanced diet.", "Keep up regular activity."],
}

ORDER = ["tongue", "eye", "nail", "palm"]


def _severity_from_prob(p_anemic: float) -> str:
    if p_anemic >= 0.70:
        return "High"
    if p_anemic >= 0.40:
        return "Moderate"
    return "Low"


def _confidence_label(conf: float) -> str:
    if conf >= 0.85:
        return "High"
    if conf >= 0.65:
        return "Moderate"
    return "Low"


def build_api_response(modality_results: dict, fusion_result: dict) -> dict:
    """Map ML results to the frontend contract."""
    p_non_anemic = fusion_result["probabilities"][0]
    score = int(round(p_non_anemic * 100))
    status = "Healthy" if fusion_result["label"] == "Non-Anemic" else "Attention"

    predictions = []
    for modality in ORDER:
        r = modality_results.get(modality)
        if r is None:
            continue
        meta = MODALITY_META[modality]
        is_anemic = r["label"] == "Anemic"

        predictions.append({
            "condition": meta["condition"],
            "confidence": round(float(r["confidence"]), 2),
            "severity": _severity_from_prob(float(r["probabilities"][1])),
            "description": (ANEMIC_DESCRIPTIONS[modality]
                            if is_anemic
                            else NON_ANEMIC_DESCRIPTIONS[modality]),
            "recommendations": (ANEMIC_RECOMMENDATIONS[modality]
                                if is_anemic
                                else NON_ANEMIC_RECOMMENDATIONS[modality]),
            "detected_from": meta["detected_from"],
            # Extra fields — ignored by current frontend, useful later
            "low_confidence": bool(r.get("low_confidence", False)),
            "raw_probabilities": [round(float(p), 4) for p in r["probabilities"]],
        })

    return {
        "summary": {
            "score": score,
            "status": status,
            "confidence": round(float(fusion_result["confidence"]), 3),
            "confidence_label": _confidence_label(float(fusion_result["confidence"])),
        },
        "predictions": predictions,
        "disclaimer": (
            "This is a screening tool only. Not a medical diagnosis. "
            "Please consult a doctor for blood tests."
        ),
        "disclaimer_tagalog": (
            "Ito ay screening tool lamang. Hindi ito medikal na diagnosis. "
            "Mangyaring kumonsulta sa doktor para sa blood test."
        ),
    }