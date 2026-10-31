import os
import base64
import io
import json
import re
import requests
from PIL import Image

GROQ_API_KEY = os.environ.get("GROQ_API_KEY")
GROQ_VISION_URL = "https://api.groq.com/openai/v1/chat/completions"
VISION_MODEL = "qwen/qwen3.8-27b"

SYSTEM_PROMPT = """
You are a medical image analyst assisting a screening tool for iron deficiency anemia.

You will receive ONE image that is a 2x2 grid showing four anatomical sites:
- TOP-LEFT: Tongue
- TOP-RIGHT: Eye conjunctiva (inner lower eyelid)
- BOTTOM-LEFT: Nail bed
- BOTTOM-RIGHT: Palm

For each of the four quadrants, write a 1-2 sentence visual description.

You MUST respond with ONLY a valid JSON object in this exact format (no markdown, no extra text):
{
  "tongue": "<description of top-left quadrant>",
  "eye": "<description of top-right quadrant>",
  "nail": "<description of bottom-left quadrant>",
  "palm": "<description of bottom-right quadrant>"
}

Rules for each description:
- Do NOT diagnose. Use phrases like "appears pale", "shows reduced pink tone", "within normal range".
- Keep language accessible (no medical jargon).
- If the site's model prediction is Anemic, emphasize visual signs consistent with pallor.
- If Non-Anemic, describe healthy appearance.
- Max 2 sentences per quadrant.
"""


def _make_collage(image_bytes_dict: dict) -> bytes:
    """Combine 4 images into a single 512x512 2x2 grid (JPEG bytes)."""
    quadrants = []
    # Order matches the prompt layout
    for modality in ["tongue", "eye", "nail", "palm"]:
        img_bytes = image_bytes_dict.get(modality)
        if not img_bytes:
            quadrants.append(Image.new("RGB", (256, 256), (128, 128, 128)))
            continue
        img = Image.open(io.BytesIO(img_bytes)).convert("RGB").resize((256, 256))
        quadrants.append(img)

    collage = Image.new("RGB", (512, 512))
    collage.paste(quadrants[0], (0, 0))       # tongue (top-left)
    collage.paste(quadrants[1], (256, 0))     # eye (top-right)
    collage.paste(quadrants[2], (0, 256))     # nail (bottom-left)
    collage.paste(quadrants[3], (256, 256))   # palm (bottom-right)

    out = io.BytesIO()
    collage.save(out, format="JPEG", quality=85)
    return out.getvalue()


def _parse_json(text: str) -> dict:
    text = text.strip()
    text = re.sub(r"^```(?:json)?\s*", "", text)
    text = re.sub(r"\s*```$", "", text)
    start, end = text.find("{"), text.rfind("}")
    if start == -1 or end == -1:
        return {}
    try:
        return json.loads(text[start:end + 1])
    except Exception:
        return {}


def describe_all_modalities(image_bytes_dict: dict, modality_results: dict) -> dict:
    """
    Combine 4 images into a 2x2 collage, send ONE API call to Qwen.
    Returns {modality: description} for each modality, or {} on failure.
    """
    if not GROQ_API_KEY:
        return {}

    try:
        collage_bytes = _make_collage(image_bytes_dict)
    except Exception as e:
        print(f"[VLM] Collage creation failed: {e}")
        return {}

    b64 = base64.b64encode(collage_bytes).decode("utf-8")

    # Build context about model predictions for each quadrant
    labels = []
    for modality in ["tongue", "eye", "nail", "palm"]:
        r = modality_results.get(modality, {})
        labels.append(f"{modality}={r.get('label', 'Unknown')}({r.get('confidence', 0):.2f})")

    user_text = (
        "The image is a 2x2 grid: top-left=tongue, top-right=eye, "
        "bottom-left=nail, bottom-right=palm. "
        f"Model predictions: {', '.join(labels)}. "
        "Return a JSON object with descriptions for each."
    )

    payload = {
        "model": VISION_MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": [
                {"type": "text", "text": user_text},
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
            ]},
        ],
        "temperature": 0.3,
        "max_tokens": 400,
        "response_format": {"type": "json_object"},
    }

    try:
        resp = requests.post(
            GROQ_VISION_URL,
            headers={"Authorization": f"Bearer {GROQ_API_KEY}", "Content-Type": "application/json"},
            json=payload,
            timeout=40,
        )
        if resp.status_code == 429:
            print(f"[VLM] Rate limit hit (429) — falling back to hardcoded descriptions")
            return {}
        if resp.status_code == 400:
            print(f"[VLM] Bad request (400): {resp.text[:200]}")
            return {}
        resp.raise_for_status()
        raw_text = resp.json()["choices"][0]["message"]["content"]
        parsed = _parse_json(raw_text)

        result = {}
        for modality in ["tongue", "eye", "nail", "palm"]:
            val = parsed.get(modality)
            if isinstance(val, str) and val.strip():
                result[modality] = val.strip()

        if result:
            print(f"[VLM] ✅ Got descriptions for {list(result.keys())}")
        else:
            print(f"[VLM] No valid descriptions parsed from response")
        return result

    except Exception as e:
        print(f"[VLM] Failed: {e}")
        return {}