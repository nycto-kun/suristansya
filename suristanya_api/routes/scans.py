"""Scan history CRUD, scoped to the authenticated user."""
import json
import os
import uuid
from datetime import datetime
from flask import Blueprint, request, jsonify, g, send_from_directory
from db import db, Scan
from utils.jwt_utils import auth_required
from utils.supabase_storage import upload_scan_image, signed_url_for

scans_bp = Blueprint("scans", __name__)
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UPLOAD_DIR = os.path.join(BASE_DIR, "uploads")
os.makedirs(UPLOAD_DIR, exist_ok=True)

def _scan_to_dict(scan: Scan) -> dict:
    # Convert Supabase paths to signed URLs for the app to download
    raw_images = json.loads(scan.images_json) if scan.images_json else {}
    signed_images = {k: signed_url_for(v) for k, v in raw_images.items()}

    return {
        "id": scan.uuid,
        "timestamp": scan.timestamp.isoformat() + "Z",
        "summary": {
            "score": scan.score,
            "status": scan.status,
            "confidence": scan.confidence,
            "confidence_label": scan.confidence_label,
        },
        "predictions": json.loads(scan.predictions_json or "[]"),
        "screening": json.loads(scan.screening_json) if scan.screening_json else None,
        "images": signed_images,
        "note": scan.note or "",
    }

@scans_bp.route("/uploads/<path:subpath>", methods=["GET"])
def serve_image(subpath):
    """Serve locally-stored images (fallback when Supabase isn't used)."""
    return send_from_directory(UPLOAD_DIR, subpath)

@scans_bp.route("", methods=["POST"])
@auth_required
def create_scan():
    scan_uuid = str(uuid.uuid4())
    timestamp_str = request.form.get("timestamp")
    
    if timestamp_str:
        try:
            ts = datetime.fromisoformat(timestamp_str.replace("Z", ""))
        except ValueError:
            ts = datetime.utcnow()
    else:
        ts = datetime.utcnow()

    # 1. Upload Images to SUPABASE
    image_paths = {}
    for key in ["tongue", "palm", "nail", "eye"]:
        if key in request.files:
            file = request.files[key]
            if file.filename:
                # USE SUPABASE UPLOAD INSTEAD OF LOCAL SAVE
                image_paths[key] = upload_scan_image(
                    file.read(), scan_uuid, key, g.current_user.uuid
                )

    # 2. Parse JSON Data
    summary = json.loads(request.form.get("summary", "{}"))
    predictions = json.loads(request.form.get("predictions", "[]"))
    screening = request.form.get("screening")
    note = request.form.get("note", "").strip()[:500]
    
    # 3. NEW: Parse raw probs
    raw_probs = request.form.get("raw_probs")
    model_version = request.form.get("model_version", "v1.0-79.4")

    # 4. Save to Database
    scan = Scan(
        uuid=scan_uuid,
        user_id=g.current_user.id,
        timestamp=ts,
        score=int(summary.get("score") or 0),
        status=str(summary.get("status") or "Unknown"),
        confidence=float(summary.get("confidence") or 0.0),
        confidence_label=str(summary.get("confidence_label") or "Low"),
        note=note,
        predictions_json=json.dumps(predictions),
        screening_json=screening if screening else None,
        images_json=json.dumps(image_paths) if image_paths else None,
        raw_probs=raw_probs,               # SAVING TO DB
        model_version=model_version        # SAVING TO DB
    )
    db.session.add(scan)
    db.session.commit()
    return jsonify(_scan_to_dict(scan)), 201

@scans_bp.route("", methods=["GET"])
@auth_required
def list_scans():
    try:
        limit = min(int(request.args.get("limit", 50)), 200)
    except ValueError:
        limit = 50
    scans = (
        Scan.query
        .filter_by(user_id=g.current_user.id)
        .order_by(Scan.timestamp.desc())
        .limit(limit)
        .all()
    )
    return jsonify({"scans": [_scan_to_dict(s) for s in scans]})

# ... (keep your existing update_scan, delete_scan, clear_scans routes unchanged) ...
@scans_bp.route("/<scan_uuid>", methods=["PATCH"])
@auth_required
def update_scan(scan_uuid):
    data = request.get_json(silent=True) or {}
    scan = Scan.query.filter_by(uuid=scan_uuid, user_id=g.current_user.id).first()
    if not scan:
        return jsonify({"error": "Scan not found"}), 404
    if "note" in data:
        scan.note = (data["note"] or "").strip()[:500]
        db.session.commit()
    return jsonify(_scan_to_dict(scan))

@scans_bp.route("/<scan_uuid>", methods=["DELETE"])
@auth_required
def delete_scan(scan_uuid):
    scan = Scan.query.filter_by(uuid=scan_uuid, user_id=g.current_user.id).first()
    if not scan:
        return jsonify({"error": "Scan not found"}), 404
    db.session.delete(scan)
    db.session.commit()
    return jsonify({"ok": True})

@scans_bp.route("", methods=["DELETE"])
@auth_required
def clear_scans():
    Scan.query.filter_by(user_id=g.current_user.id).delete()
    db.session.commit()
    return jsonify({"ok": True})