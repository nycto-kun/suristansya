# utils/supabase_storage.py — FULL REPLACEMENT
"""Upload scan images to Supabase Storage with organized local fallback."""
import os
import pathlib
from supabase import create_client

SUPABASE_URL = os.environ.get('SUPABASE_URL')
SUPABASE_KEY = os.environ.get('SUPABASE_SERVICE_KEY')
SUPABASE_BUCKET = os.environ.get('SUPABASE_BUCKET', 'suristanya-scans')
LOCAL_FALLBACK = os.environ.get('STORAGE_FALLBACK_LOCAL', 'true').lower() == 'true'

LOCAL_DIR = pathlib.Path(__file__).parent.parent / 'uploads'

_supabase = None


def _client():
    global _supabase
    if _supabase is None and SUPABASE_URL and SUPABASE_KEY:
        try:
            _supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
            print(f"[storage] Supabase client initialized for {SUPABASE_URL}")
        except Exception as e:
            print(f"[storage] FATAL: Supabase client init failed: {e}")
    return _supabase


def upload_scan_image(image_bytes: bytes, scan_uuid: str, modality: str, user_uuid: str) -> str:
    """
    Uploads to Supabase Storage OR falls back to organized local storage.
    
    Supabase path:  scans/{user_uuid}/{scan_uuid}/{modality}.jpg
    Local path:     uploads/{user_uuid}/{scan_uuid}/{modality}.jpg
    """
    storage_path = f"scans/{user_uuid}/{scan_uuid}/{modality}.jpg"

    client = _client()
    if client is not None:
        try:
            client.storage.from_(SUPABASE_BUCKET).upload(
                path=storage_path,
                file=image_bytes,
                file_options={"content-type": "image/jpeg", "upsert": "true"}
            )
            print(f"[storage] ✅ Supabase: {storage_path}")
            return storage_path
        except Exception as e:
            print(f"[storage] ❌ Supabase upload FAILED for {storage_path}:")
            print(f"[storage]    Reason: {type(e).__name__}: {e}")
            if not LOCAL_FALLBACK:
                raise RuntimeError(f"Supabase upload failed and fallback disabled: {e}")
    else:
        print(f"[storage] ❌ No Supabase client (check .env keys)")

    # Organized local fallback: uploads/{user_uuid}/{scan_uuid}/{modality}.jpg
    local_path = LOCAL_DIR / user_uuid / scan_uuid / f"{modality}.jpg"
    local_path.parent.mkdir(parents=True, exist_ok=True)
    local_path.write_bytes(image_bytes)
    print(f"[storage] 💾 Local fallback: {local_path}")
    return f"/scans/uploads/{user_uuid}/{scan_uuid}/{modality}.jpg"


def signed_url_for(path: str) -> str:
    """Convert a Supabase storage path to a temporary URL. Local paths pass through."""
    if path.startswith('/scans/uploads/'):
        return path
    client = _client()
    if client:
        try:
            res = client.storage.from_(SUPABASE_BUCKET).create_signed_url(path, 3600)
            return res.get('signedURL') or res.get('signed_url') or path
        except Exception as e:
            print(f"[storage] signed_url failed for {path}: {e}")
    return path