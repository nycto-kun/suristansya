from flask import Blueprint, request, jsonify

from rules.iron_deficiency import assess

screen_bp = Blueprint("screen", __name__)


@screen_bp.route("/assess", methods=["POST"])
def screen_assess():
    """
    Accepts JSON:
      {sex, pregnant, age, symptoms: [...], risk_factors: [...], labs: {...}}
    Returns the rule-engine result.
    """
    data = request.get_json(silent=True) or {}
    result = assess(data)
    return jsonify(result)


@screen_bp.route("/schema", methods=["GET"])
def screen_schema():
    """Returns the lists of symptoms and risk factors for the frontend."""
    from rules.iron_deficiency import SYMPTOMS, RISK_FACTORS, RED_FLAGS
    return jsonify({
        "symptoms": SYMPTOMS,
        "risk_factors": RISK_FACTORS,
        "red_flags": RED_FLAGS,
    })