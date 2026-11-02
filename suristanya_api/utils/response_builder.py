MODALITY_META = {
    "tongue": {"condition": "Tongue Pallor",         "detected_from": ["Tongue"]},
    "eye":    {"condition": "Eye Conjunctiva Pallor","detected_from": ["Eye"]},
    "nail":   {"condition": "Nail Bed Pallor",       "detected_from": ["Nail"]},
    "palm":   {"condition": "Palm Pallor",           "detected_from": ["Palm"]},
}

ANEMIC_DESCRIPTIONS = {
    "tongue": "Visual markers suggest possible pallor or smoothness on the tongue — a pattern sometimes associated with iron deficiency.",
    "eye":    "The conjunctiva shows signs of pallor, a common non-invasive visual indicator used in anemia screening.",
    "nail":   "Nail bed appears pale or lacks the typical pink tone — this can be linked to low iron over time.",
    "palm":   "Palm creases and color suggest reduced perfusion, which may indicate anemia.",
}

NON_ANEMIC_DESCRIPTIONS = {
    "tongue": "Tongue surface appears normally colored and textured.",
    "eye":    "Conjunctiva appears pink and well-perfused.",
    "nail":   "Nail bed shows a healthy pink tone.",
    "palm":   "Palm color and creases appear within the normal range.",
}

# PURELY NUTRITIONAL ADVICE (No clinical/CBC recommendations)
ANEMIC_RECOMMENDATIONS = {
    "tongue": [
        "Increase intake of iron-rich foods like liver, lean meat, and dark leafy greens.",
        "Pair plant-based iron with Vitamin C (e.g., calamansi, tomatoes) to boost absorption.",
        "Avoid drinking coffee or tea immediately after meals as they inhibit iron absorption."
    ],
    "eye": [
        "Focus on a diet rich in iron (beans, lentils) and Vitamin B12 (eggs, fish).",
        "Include Vitamin C-rich fruits like guava and citrus to enhance iron uptake."
    ],
    "nail": [
        "Incorporate iron-fortified cereals and leafy greens into your daily meals.",
        "Ensure adequate protein intake to support healthy nail and blood cell growth."
    ],
    "palm": [
        "Eat a balanced diet with iron-rich proteins (fish, poultry) and legumes.",
        "Stay hydrated and include folate-rich foods (broccoli, avocado) in your meals."
    ],
}

NON_ANEMIC_RECOMMENDATIONS = {
    "tongue": [
        "Maintain a well-balanced diet with a variety of colorful vegetables.",
        "Continue consuming iron-rich foods to maintain healthy blood oxygen levels."
    ],
    "eye": [
        "Keep up your intake of Vitamin A and C for overall tissue health.",
        "Maintain an iron-conscious diet to prevent future deficiencies."
    ],
    "nail": [
        "Continue routine nail care and maintain adequate protein and iron intake.",
        "Stay hydrated and eat a diverse range of whole foods."
    ],
    "palm": [
        "Maintain your current healthy dietary habits.",
        "Keep up regular physical activity and balanced nutrition."
    ],
}

ORDER = ["tongue", "eye", "nail", "palm"]


def _severity_from_prob(p_anemic: float) -> str:
    if p_anemic >= 0.70: return "High"
    if p_anemic >= 0.40: return "Moderate"
    return "Low"


def _confidence_label(conf: float) -> str:
    if conf >= 0.85: return "High"
    if conf >= 0.65: return "Moderate"
    return "Low"


def build_api_response(modality_results: dict, fusion_result: dict, vlm_descriptions: dict = None) -> dict:
    p_non_anemic = fusion_result["probabilities"][0]
    score = int(round(p_non_anemic * 100))
    
    # CHANGED: "Healthy" -> "Non-Anemic"
    status = "Non-Anemic" if fusion_result["label"] == "Non-Anemic" else "Anemic"

    predictions = []
    for modality in ORDER:
        r = modality_results.get(modality)
        if r is None: continue
        meta = MODALITY_META[modality]
        is_anemic = r["label"] == "Anemic"

        # Use VLM description if available, else fallback
        if vlm_descriptions and vlm_descriptions.get(modality):
            description = vlm_descriptions[modality]
        else:
            description = (ANEMIC_DESCRIPTIONS[modality] if is_anemic else NON_ANEMIC_DESCRIPTIONS[modality])

        predictions.append({
            "condition": meta["condition"],
            "confidence": round(float(r["confidence"]), 2),
            "severity": _severity_from_prob(float(r["probabilities"][1])),
            "description": description,
            "recommendations": (ANEMIC_RECOMMENDATIONS[modality] if is_anemic else NON_ANEMIC_RECOMMENDATIONS[modality]),
            "detected_from": meta["detected_from"],
            "low_confidence": bool(r.get("low_confidence", False)),
            "raw_probabilities": [round(float(p), 4) for p in r["probabilities"]],
        })

    return {
        "summary": {
            "score": score,
            "status": status, # Now "Non-Anemic"
            "confidence": round(float(fusion_result["confidence"]), 3),
            "confidence_label": _confidence_label(float(fusion_result["confidence"])),
        },
        "predictions": predictions,
        "disclaimer": (
            "This is a nutritional screening tool only. Not a medical diagnosis. "
            "Please consult a healthcare professional for medical concerns."
        ),
        "disclaimer_tagalog": (
            "Ito ay nutritional screening tool lamang. Hindi ito medikal na diagnosis. "
            "Mangyaring kumonsulta sa propesyonal sa kalusugan para sa mga medikal na alalahanin."
        ),
    }