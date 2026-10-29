from flask import Blueprint, request, jsonify
import re

chat_bp = Blueprint("chat", __name__)


# ─── KNOWLEDGE BASE ─────────────────────────────────────────────
# Each topic has keywords (trigger phrases) and an answer.
# "suggestions" are follow-up topics to show as quick-reply chips.

KB = {
    "anemia": {
        "keywords": [
            "anemia", "anaemia", "low blood", "low hemoglobin",
            "pale skin", "paleness", "pallor", "low iron",
        ],
        "answer": (
            "Anemia means your blood has fewer healthy red blood cells "
            "or less hemoglobin than normal, so your tissues get less oxygen. "
            "Common signs: fatigue, pale skin, shortness of breath, dizziness, "
            "cold hands and feet. Causes include iron, B12 or folate deficiency, "
            "chronic disease, and blood loss. A CBC blood test confirms it."
        ),
        "suggestions": ["Iron-rich foods", "B12 deficiency", "When to see a doctor"],
    },
    "iron": {
        "keywords": [
            "iron", "iron-rich", "iron rich", "iron foods",
            "spinach", "lentils", "red meat",
        ],
        "answer": (
            "Iron-rich foods include red meat, liver, chicken, fish, spinach, "
            "lentils, chickpeas, beans, tofu, and fortified cereals. "
            "Pair them with vitamin C (citrus, tomato, bell pepper) to boost "
            "absorption. Avoid tea, coffee, or calcium right after meals — "
            "they block iron uptake."
        ),
        "suggestions": ["Vitamin C", "B12 deficiency", "Folate"],
    },
    "vitamin-c": {
        "keywords": [
            "vitamin c", "vit c", "ascorbic", "citrus", "orange",
            "lemon", "absorption",
        ],
        "answer": (
            "Vitamin C significantly boosts iron absorption — up to 3x when "
            "eaten with iron-rich foods. Good sources: oranges, lemons, "
            "guava, tomatoes, bell peppers, broccoli, and strawberries. "
            "A squeeze of lemon over spinach or lentils makes a real difference."
        ),
        "suggestions": ["Iron-rich foods", "Anemia", "Diet tips"],
    },
    "b12": {
        "keywords": [
            "b12", "cobalamin", "b-12", "vitamin b12", "pernicious",
        ],
        "answer": (
            "Vitamin B12 deficiency causes a type of anemia with fatigue, "
            "tingling in hands and feet, memory issues, and a smooth, sore "
            "tongue. Main sources: meat, fish, eggs, dairy, and fortified "
            "cereals. Vegans and older adults are at higher risk and may "
            "need supplements."
        ),
        "suggestions": ["Folate", "Anemia", "When to see a doctor"],
    },
    "folate": {
        "keywords": [
            "folate", "folic acid", "vitamin b9", "b9", "pregnancy vitamin",
        ],
        "answer": (
            "Folate (vitamin B9) is needed to make red blood cells. "
            "Deficiency causes a type of anemia similar to B12 deficiency. "
            "Sources: leafy greens, legumes, citrus, fortified grains. "
            "Pregnant women need extra folate to prevent neural tube defects."
        ),
        "suggestions": ["Pregnancy", "Anemia", "Iron-rich foods"],
    },
    "hydration": {
        "keywords": [
            "hydration", "dehydrat", "water", "drink", "thirsty", "dry mouth",
        ],
        "answer": (
            "Aim for 2–3 liters of water daily, more if active or in hot "
            "weather. Signs of dehydration: dark yellow urine, dry mouth, "
            "fatigue, headache, dizziness. A pale, straw-colored urine "
            "means you're well hydrated."
        ),
        "suggestions": ["Fatigue", "Dizziness", "Diet tips"],
    },
    "pallor": {
        "keywords": [
            "pallor", "pale", "paleness", "whitish", "washed out", "colorless",
        ],
        "answer": (
            "Pallor is unusual paleness of the skin or mucous membranes. "
            "It's most visible in the palms, lower eyelid, nail beds, and "
            "inside the mouth. While often benign, persistent pallor can "
            "signal anemia or poor circulation — worth a doctor's check."
        ),
        "suggestions": ["Anemia", "Eye conjunctiva", "Nail health"],
    },
    "tongue": {
        "keywords": [
            "tongue", "taste", "coating", "smooth tongue", "sore tongue",
        ],
        "answer": (
            "A healthy tongue is pink with a thin white coating. "
            "A smooth, shiny, or beefy-red tongue can signal B12 or iron "
            "deficiency. A pale tongue may indicate anemia. Very dry tongue "
            "suggests dehydration. Persistent changes should be checked."
        ),
        "suggestions": ["B12 deficiency", "Hydration", "Anemia"],
    },
    "nail": {
        "keywords": [
            "nail", "nails", "nail bed", "brittle nails", "ridges",
            "koilonychia", "spoon nails",
        ],
        "answer": (
            "Healthy nail beds are pink. Pale nail beds can indicate anemia. "
            "Spoon-shaped nails (koilonychia) are a classic sign of long-term "
            "iron deficiency. Vertical ridges are usually normal with age; "
            "horizontal ridges or white spots may need investigation."
        ),
        "suggestions": ["Iron-rich foods", "Anemia", "Pallor"],
    },
    "eye": {
        "keywords": [
            "eye", "conjunctiva", "eyelid", "pale eyelid", "inner eyelid",
        ],
        "answer": (
            "The conjunctiva (inner lower eyelid) is one of the best places "
            "to check for pallor. Gently pull down the lower lid — a healthy "
            "one is pink or red; a pale one can suggest anemia. This is a "
            "common, non-invasive screening method used in clinics."
        ),
        "suggestions": ["Anemia", "Pallor", "When to see a doctor"],
    },
    "fatigue": {
        "keywords": [
            "fatigue", "tired", "tiredness", "exhausted", "no energy",
            "weakness", "lethargic",
        ],
        "answer": (
            "Persistent fatigue has many causes — poor sleep, stress, "
            "dehydration, anemia, thyroid issues, or vitamin deficiencies. "
            "If you're tired most days for weeks despite adequate sleep, "
            "see a doctor for a basic blood panel."
        ),
        "suggestions": ["Anemia", "B12 deficiency", "Hydration"],
    },
    "dizziness": {
        "keywords": [
            "dizzy", "dizziness", "lightheaded", "faint", "vertigo",
        ],
        "answer": (
            "Occasional dizziness is common with dehydration, low blood "
            "sugar, or standing up too fast. Recurrent dizziness, especially "
            "with fatigue and pallor, may point to anemia or low blood "
            "pressure. Get it checked if it's frequent or you've fainted."
        ),
        "suggestions": ["Anemia", "Hydration", "When to see a doctor"],
    },
    "menstruation": {
        "keywords": [
            "period", "menstruation", "menstrual", "heavy bleeding",
            "heavy period",
        ],
        "answer": (
            "Heavy menstrual bleeding is one of the most common causes of "
            "iron-deficiency anemia in women. If your period lasts over "
            "7 days, soaks a pad every hour, or you feel exhausted during it, "
            "talk to a doctor. Iron supplementation is often recommended."
        ),
        "suggestions": ["Iron-rich foods", "Anemia", "When to see a doctor"],
    },
    "pregnancy": {
        "keywords": [
            "pregnant", "pregnancy", "expecting", "prenatal",
        ],
        "answer": (
            "Pregnancy increases iron and folate needs significantly. "
            "Prenatal vitamins usually cover both. Regular CBC checks help "
            "catch anemia early. Never start supplements without your "
            "OB-GYN's guidance during pregnancy."
        ),
        "suggestions": ["Folate", "Iron-rich foods", "When to see a doctor"],
    },
    "diet": {
        "keywords": [
            "diet", "nutrition", "eat", "foods", "meal", "healthy eating",
        ],
        "answer": (
            "For overall health and to prevent anemia: eat a variety of "
            "colorful vegetables, lean proteins, whole grains, legumes, and "
            "healthy fats. Pair iron-rich foods with vitamin C, stay hydrated, "
            "and limit ultra-processed foods and excess caffeine around meals."
        ),
        "suggestions": ["Iron-rich foods", "Vitamin C", "Hydration"],
    },
    "scan": {
        "keywords": [
            "scan", "how does it work", "how it works", "capture",
            "photo", "image", "camera",
        ],
        "answer": (
            "The scan works in 3 steps: (1) Answer a few quick questions. "
            "(2) Capture 4 images — tongue, palm, nail, and inner eyelid — "
            "in bright, even light. (3) Our AI screens them for visual signs "
            "like pallor, then shows you a health score with recommendations."
        ),
        "suggestions": ["Accuracy", "Results", "Privacy"],
    },
    "accuracy": {
        "keywords": [
            "accurate", "accuracy", "reliable", "trust", "correct",
            "how good", "how precise",
        ],
        "answer": (
            "Suristanya is a screening tool, not a diagnostic device. "
            "It detects visual patterns that correlate with conditions like "
            "anemia, but it can't replace a blood test. Think of it as an "
            "early nudge — if it flags something, follow up with a doctor."
        ),
        "suggestions": ["Results", "When to see a doctor", "Privacy"],
    },
    "results": {
        "keywords": [
            "result", "results", "score", "confidence", "severity",
            "what does it mean", "interpret",
        ],
        "answer": (
            "Your health score (0–100) summarizes overall signals. Each "
            "finding shows a confidence percentage and severity (Low, "
            "Moderate, High). High confidence + High severity = worth a "
            "doctor visit. Remember: confidence means how sure the AI is "
            "about the visual pattern, not how serious your condition is."
        ),
        "suggestions": ["When to see a doctor", "Accuracy", "Anemia"],
    },
    "privacy": {
        "keywords": [
            "privacy", "data", "store", "secure", "gdpr", "delete my",
        ],
        "answer": (
            "Your images are processed only for analysis and aren't shared "
            "with third parties. You can request deletion of your data at "
            "any time from Settings. We don't sell user data — ever."
        ),
        "suggestions": ["Accuracy", "Scan", "Results"],
    },
    "doctor": {
        "keywords": [
            "doctor", "physician", "clinic", "hospital", "see a doctor",
            "medical advice", "should i see",
        ],
        "answer": (
            "See a doctor if: your symptoms are persistent or worsening, "
            "you have severe fatigue or shortness of breath, you've fainted, "
            "or the scan flags Moderate/High severity findings. A simple "
            "CBC blood test can confirm anemia and guide treatment."
        ),
        "suggestions": ["Anemia", "Results", "Accuracy"],
    },
    # ─── Small talk ──────────────────────────────────────────
    "greeting": {
        "keywords": [
            "hi", "hello", "hey", "good morning", "good afternoon",
            "good evening", "howdy",
        ],
        "answer": (
            "Hi! I'm Ava 🌿 your health assistant. I can help with anemia, "
            "iron, hydration, nutrition, or questions about your scan."
        ),
        "suggestions": ["Start a scan", "Anemia", "Iron-rich foods", "Hydration"],
    },
    "thanks": {
        "keywords": ["thanks", "thank you", "thx", "appreciate", "ty"],
        "answer": (
            "You're welcome! 🌱 Let me know if you want to explore another "
            "topic or start a scan."
        ),
        "suggestions": ["Start a scan", "Anemia", "Iron-rich foods"],
    },
    "bye": {
        "keywords": ["bye", "goodbye", "see you", "later", "cya"],
        "answer": (
            "Take care! Come back anytime — I'm here to help you stay on "
            "top of your health. 💚"
        ),
        "suggestions": [],
    },
    "help": {
        "keywords": ["help", "what can you do", "topics", "options"],
        "answer": (
            "I can talk about: anemia, iron-rich foods, vitamin C, B12, "
            "folate, hydration, pallor, tongue health, nail health, eye "
            "conjunctiva, fatigue, dizziness, menstruation, pregnancy, "
            "diet, how the scan works, accuracy, results, and privacy."
        ),
        "suggestions": ["Anemia", "Iron-rich foods", "Scan", "Results"],
    },
}

FALLBACK = {
    "answer": (
        "I'm still learning. Try asking about anemia, iron, hydration, "
        "nutrition, your scan, or the results — or type 'help' to see "
        "the full list of topics."
    ),
    "suggestions": ["Anemia", "Iron-rich foods", "Scan", "Help"],
}


# ─── MATCHING ENGINE ────────────────────────────────────────────

def _normalize(text: str) -> str:
    text = text.lower()
    text = re.sub(r"[^\w\s]", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def _score(topic_key: str, topic: dict, query: str) -> float:
    """Higher = better match. Substring matches on keyword phrases win."""
    score = 0.0
    for kw in topic["keywords"]:
        kw_norm = _normalize(kw)
        if not kw_norm:
            continue
        if kw_norm in query:
            # Bonus for multi-word phrases
            score += 1.0 + (0.5 * len(kw_norm.split()))
    # Small bonus if the topic name appears
    if topic_key.replace("-", " ") in query:
        score += 1.0
    return score


def _find_best(query: str):
    best_key, best_score = None, 0.0
    for key, topic in KB.items():
        s = _score(key, topic, query)
        if s > best_score:
            best_key, best_score = key, s
    return best_key, best_score


def _reply(message: str, history: list) -> dict:
    query = _normalize(message)

    if not query:
        return {"reply": "Could you type your question?", "suggestions": []}

    # Context: if the query is vague ("tell me more"), reuse last intent
    vague_phrases = ["tell me more", "more", "continue", "go on", "explain"]
    if any(p in query for p in vague_phrases) and history:
        for msg in reversed(history):
            if msg.get("role") == "user":
                last_q = _normalize(msg.get("text", ""))
                key, score = _find_best(last_q)
                if score > 0:
                    topic = KB[key]
                    return {
                        "reply": topic["answer"],
                        "suggestions": topic["suggestions"],
                        "intent": key,
                        "confidence": round(score, 2),
                    }
                break

    key, score = _find_best(query)

    # Threshold: require at least one keyword hit
    if key and score >= 1.0:
        topic = KB[key]
        return {
            "reply": topic["answer"],
            "suggestions": topic["suggestions"],
            "intent": key,
            "confidence": round(score, 2),
        }

    return {
        "reply": FALLBACK["answer"],
        "suggestions": FALLBACK["suggestions"],
        "intent": "fallback",
        "confidence": 0.0,
    }


# ─── ROUTE ──────────────────────────────────────────────────────

@chat_bp.route("/", methods=["POST"])
def chat():
    data = request.get_json(silent=True) or {}
    message = (data.get("message") or "").strip()
    history = data.get("history") or []

    if not message:
        return jsonify({"error": "message is required"}), 400

    return jsonify(_reply(message, history))