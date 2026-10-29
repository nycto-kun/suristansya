"""SQLAlchemy setup and ORM models for Suristanya."""
import os
from datetime import datetime

from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, "suristanya.db")


class User(db.Model):
    __tablename__ = "users"

    id = db.Column(db.Integer, primary_key=True)
    uuid = db.Column(db.String(36), unique=True, nullable=False, index=True)
    name = db.Column(db.String(120), nullable=False)
    email = db.Column(db.String(200), unique=True, nullable=False, index=True)
    password_hash = db.Column(db.String(255), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    scans = db.relationship(
        "Scan",
        backref="user",
        lazy="dynamic",
        cascade="all, delete-orphan",
    )

    def to_dict(self):
        return {"id": self.uuid, "name": self.name, "email": self.email}


class Scan(db.Model):
    """One completed screening/scan session for a user."""

    __tablename__ = "scans"

    id = db.Column(db.Integer, primary_key=True)
    uuid = db.Column(db.String(36), unique=True, nullable=False, index=True)
    user_id = db.Column(
        db.Integer, db.ForeignKey("users.id"), nullable=False, index=True
    )
    timestamp = db.Column(db.DateTime, nullable=False, index=True)

    # Flattened summary columns so we can sort/filter without parsing JSON
    score = db.Column(db.Integer, nullable=False, default=0)
    status = db.Column(db.String(50), nullable=False, default="Unknown")
    confidence = db.Column(db.Float, nullable=False, default=0.0)
    confidence_label = db.Column(db.String(20), nullable=False, default="Low")

    note = db.Column(db.Text, nullable=False, default="")

    # JSON blobs preserve the exact API shape the Flutter client uses
    predictions_json = db.Column(db.Text, nullable=False, default="[]")
    screening_json = db.Column(db.Text, nullable=True)
    
    # ADDED THIS LINE:
    images_json = db.Column(db.Text, nullable=True)

    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)