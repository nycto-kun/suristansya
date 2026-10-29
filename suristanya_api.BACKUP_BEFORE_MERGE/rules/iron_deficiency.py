"""
Iron deficiency screening rules.

NOT a diagnosis. Screening only.
Thresholds follow WHO ferritin guidance (2020), NICE NG24,
and ASH iron deficiency guidance — check local guidelines
before using clinically.
"""

from typing import Any, Dict, List, Optional


# ─── KNOWLEDGE BASE ─────────────────────────────────────────────

RED_FLAGS = {
    "chest_pain": "Chest pain",
    "syncope": "Fainting or loss of consciousness",
    "severe_dyspnea": "Severe difficulty breathing",
    "active_gi_bleeding": "Active GI bleeding (vomiting blood, black stools)",
}

SYMPTOMS = {
    "fatigue": "Fatigue or tiredness",
    "pallor": "Pale skin, palms, or eyelids",
    "shortness_of_breath": "Shortness of breath",
    "pica": "Craving non-food items (ice, dirt, paper)",
    "restless_legs": "Restless legs at night",
    "hair_loss": "Hair thinning or loss",
    "dizziness": "Dizziness or lightheadedness",
    "cold_extremities": "Cold hands and feet",
    "headache": "Frequent headaches",
    "palpitations": "Racing or pounding heartbeat",
    "smooth_tongue": "Smooth, sore, or pale tongue",
    "brittle_nails": "Brittle, ridged, or spoon-shaped nails",
}

RISK_FACTORS = {
    "heavy_menstruation": "Heavy menstrual bleeding",
    "pregnancy": "Pregnancy",
    "gi_bleeding_history": "History of GI bleeding",
    "nsaid_use": "Regular NSAID use",
    "celiac": "Celiac disease",
    "ibd": "Inflammatory bowel disease",
    "bariatric_surgery": "Bariatric surgery",
    "vegan_vegetarian": "Vegan or vegetarian diet",
    "frequent_blood_donation": "Frequent blood donation",
    "ckd": "Chronic kidney disease",
    "heart_failure": "Heart failure",
}

SOURCES = {
    "who_ferritin": "WHO guideline on ferritin thresholds (2020)",
    "nice_ida": "NICE guideline NG24 — Iron deficiency anaemia",
    "ash_ferritin": "American Society of Hematology — Iron deficiency guidance",
    "who_hb": "WHO haemoglobin thresholds for anaemia",
}

HEADLINES = {
    "urgent": "Seek urgent medical care",
    "likely_ida": "Likely iron deficiency anemia",
    "likely_iron_deficiency": "Likely iron deficiency",
    "possible_iron_deficiency": "Possible iron deficiency",
    "needs_testing": "Testing recommended",
    "low_risk": "Low risk from screening",
}

MESSAGES = {
    "likely_ida": (
        "Your results are consistent with iron deficiency anemia. "
        "This is not a diagnosis — please confirm with a clinician."
    ),
    "likely_iron_deficiency": (
        "Your results are consistent with iron deficiency. "
        "Please confirm with a clinician before starting treatment."
    ),
    "possible_iron_deficiency": (
        "Your results may fit iron deficiency, but inflammation can raise ferritin. "
        "A clinician can help interpret them."
    ),
    "needs_testing": (
        "Your answers suggest you should be tested. "
        "Ask a clinician for a CBC and ferritin blood test."
    ),
    "low_risk": (
        "No strong signs from this screening — but only blood tests can rule out iron deficiency."
    ),
}


# ─── HELPERS ────────────────────────────────────────────────────

def _to_float(v: Any) -> Optional[float]:
    if v is None:
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def _to_str_set(v: Any) -> set:
    """Convert an arbitrary JSON list into a set of strings."""
    if not v:
        return set()
    if not isinstance(v, (list, tuple, set)):
        return set()
    return {str(item) for item in v if item is not None}


def _labels_for(mapping: Dict[str, str], keys: set) -> str:
    """Comma-separated human labels for a set of keys, falling back to the key."""
    labels: List[str] = []
    for k in keys:
        label: str = mapping.get(k) or k
        labels.append(label)
    return ", ".join(labels)


def _low_hemoglobin(sex: Optional[str], pregnant: bool, hb: float) -> bool:
    """WHO anaemia thresholds by sex and pregnancy."""
    if pregnant:
        return hb < 11.0
    if sex == "female":
        return hb < 12.0
    if sex == "male":
        return hb < 13.0
    return hb < 12.0  # conservative default


def _finding(rule_id: str, label: str, detail: str, source: str) -> Dict[str, str]:
    return {"id": rule_id, "label": label, "detail": detail, "source": source}


def _result(
    level: str,
    findings: List[Dict[str, str]],
    recommendations: List[str],
    context: Dict[str, Any],
) -> Dict[str, Any]:
    return {
        "level": level,
        "headline": HEADLINES[level],
        "message": MESSAGES[level],
        "findings": findings,
        "recommendations": recommendations,
        "context": context,
        "disclaimer": (
            "This is a screening tool, not a diagnosis. "
            "Always consult a qualified clinician for medical advice."
        ),
    }


# ─── MAIN ENGINE ────────────────────────────────────────────────

def assess(data: Dict[str, Any]) -> Dict[str, Any]:
    """
    data = {
      sex: 'female' | 'male' | null,
      pregnant: bool,
      age: int | null,
      symptoms: [str, ...],         # keys from SYMPTOMS or RED_FLAGS
      risk_factors: [str, ...],     # keys from RISK_FACTORS
      labs: {ferritin, hemoglobin, mcv, mch, rdw, tsat, crp}
    }
    """
    symptoms = _to_str_set(data.get("symptoms"))
    risk_factors = _to_str_set(data.get("risk_factors"))
    labs: Dict[str, Any] = data.get("labs") or {}
    sex_raw = data.get("sex")
    sex: Optional[str] = str(sex_raw).lower() if sex_raw else None
    pregnant: bool = bool(data.get("pregnant", False))
    context = {"sex": sex, "pregnant": pregnant, "age": data.get("age")}

    findings: List[Dict[str, str]] = []
    recommendations: List[str] = []

    # ── 1. RED FLAGS ALWAYS WIN ─────────────────────────────
    triggered = [k for k in RED_FLAGS if k in symptoms]
    if triggered:
        findings.append(_finding(
            "red_flag",
            "Urgent warning signs",
            "You reported: " + ", ".join(RED_FLAGS[k] for k in triggered),
            "Safety layer",
        ))
        return _result(
            "urgent",
            findings,
            [
                "Call emergency services or go to the nearest ER immediately.",
                "Do not wait for lab results before seeking care.",
            ],
            context,
        )

    # ── 2. LAB-BASED RULES (only if labs provided) ──────────
    ferritin = _to_float(labs.get("ferritin"))
    hb = _to_float(labs.get("hemoglobin"))
    mcv = _to_float(labs.get("mcv"))
    rdw = _to_float(labs.get("rdw"))
    tsat = _to_float(labs.get("tsat"))
    crp = _to_float(labs.get("crp"))

    if ferritin is not None and ferritin < 30:
        # Check low Hb for IDA
        if hb is not None and _low_hemoglobin(sex, pregnant, hb):
            findings.append(_finding(
                "ferritin_low_hb_low",
                "Low ferritin + low hemoglobin",
                f"Ferritin {ferritin} ng/mL and hemoglobin {hb} g/dL are both below threshold.",
                SOURCES["nice_ida"],
            ))
            return _result(
                "likely_ida",
                findings,
                [
                    "See a clinician to confirm the diagnosis and start treatment.",
                    "Do not start iron supplements without medical advice.",
                    "Ask about the underlying cause (menstrual loss, GI bleeding, diet).",
                ],
                context,
            )

        findings.append(_finding(
            "ferritin_low",
            "Low ferritin",
            f"Ferritin {ferritin} ng/mL is below the 30 ng/mL threshold.",
            SOURCES["who_ferritin"],
        ))

        # Supporting CBC evidence
        if mcv is not None and mcv < 80:
            findings.append(_finding(
                "mcv_low",
                "Low MCV",
                f"MCV {mcv} fL — smaller-than-normal red blood cells.",
                SOURCES["who_hb"],
            ))
        if rdw is not None and rdw > 14.5:
            findings.append(_finding(
                "rdw_high",
                "Elevated RDW",
                f"RDW {rdw}% — variability in red blood cell size.",
                SOURCES["who_hb"],
            ))

        return _result(
            "likely_iron_deficiency",
            findings,
            [
                "See a clinician to confirm iron deficiency.",
                "Ask about iron supplementation and dietary changes.",
                "Investigate the underlying cause.",
            ],
            context,
        )

    # Borderline ferritin with inflammation
    if (
        ferritin is not None
        and 30 <= ferritin < 100
        and crp is not None
        and crp > 5
        and tsat is not None
        and tsat < 20
    ):
        findings.append(_finding(
            "ferritin_borderline_inflamed",
            "Borderline ferritin with inflammation",
            f"Ferritin {ferritin} ng/mL, CRP {crp} mg/L, TSAT {tsat}%. "
            "Inflammation can artificially raise ferritin.",
            SOURCES["ash_ferritin"],
        ))
        return _result(
            "possible_iron_deficiency",
            findings,
            [
                "Ask a clinician to interpret ferritin in the context of CRP.",
                "Discuss repeating the test once inflammation subsides.",
                "Mention your symptoms and risk factors.",
            ],
            context,
        )

    # Low Hb without other evidence
    if hb is not None and _low_hemoglobin(sex, pregnant, hb):
        findings.append(_finding(
            "hb_low_only",
            "Low hemoglobin",
            f"Hemoglobin {hb} g/dL is below the reference threshold.",
            SOURCES["who_hb"],
        ))
        return _result(
            "needs_testing",
            findings,
            [
                "Ask a clinician for ferritin, TSAT, and CBC follow-up.",
                "Do not assume the cause — many conditions cause low hemoglobin.",
            ],
            context,
        )

    # ── 3. SYMPTOMS / RISK FACTORS WITHOUT LABS ─────────────
    if symptoms or risk_factors:
        if symptoms:
            findings.append(_finding(
                "symptoms_present",
                "Symptoms suggestive of iron deficiency",
                "You reported: " + _labels_for(SYMPTOMS, symptoms),
                SOURCES["nice_ida"],
            ))
        if risk_factors:
            findings.append(_finding(
                "risk_factors_present",
                "Risk factors for iron deficiency",
                "You reported: " + _labels_for(RISK_FACTORS, risk_factors),
                SOURCES["ash_ferritin"],
            ))
        return _result(
            "needs_testing",
            findings,
            [
                "Ask a clinician for a CBC and ferritin blood test.",
                "Note any recent changes in diet, menstruation, or digestion.",
                "Do not start iron supplements without medical guidance.",
            ],
            context,
        )

    # ── 4. LOW RISK ─────────────────────────────────────────
    findings.append(_finding(
        "no_concerns",
        "No strong signs from screening",
        "No symptoms or risk factors were reported.",
        "Safety layer",
    ))
    return _result(
        "low_risk",
        findings,
        [
            "Continue a balanced diet rich in iron and vitamin C.",
            "If you develop symptoms, re-screen or see a clinician.",
            "Only blood tests can rule out iron deficiency.",
        ],
        context,
    )