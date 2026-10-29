"""Scan history CRUD, scoped to the authenticated user."""
import json
import os
import uuid
from datetime import datetime
from werkzeug.utils import secure_filename
from flask import Blueprint, request, jsonify, g, send_from_directory

from db import db, Scan
from utils.jwt_utils import auth_required

scans_bp = Blueprint("scans", __name__)

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UPLOAD_DIR = os.path.join(BASE_DIR, "uploads")
os.makedirs(UPLOAD_DIR, exist_ok=True)

def _scan_to_dict(scan: Scan) -> dict:
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
        "images": json.loads(scan.images_json) if scan.images_json else {},
        "note": scan.note or "",
    }

@scans_bp.route("/uploads/<filename>", methods=["GET"])
def serve_image(filename):
    return send_from_directory(UPLOAD_DIR, filename)

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

    # Handle Images
    image_paths = {}
    for key in ["tongue", "palm", "nail", "eye"]:
        if key in request.files:
            file = request.files[key]
            if file.filename:
                filename = secure_filename(f"{scan_uuid}_{key}.jpg")
                filepath = os.path.join(UPLOAD_DIR, filename)
                file.save(filepath)
                image_paths[key] = f"/scans/uploads/{filename}"

    # Handle JSON Data
    summary = json.loads(request.form.get("summary", "{}"))
    predictions = json.loads(request.form.get("predictions", "[]"))
    screening = request.form.get("screening")
    note = request.form.get("note", "").strip()[:500]

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