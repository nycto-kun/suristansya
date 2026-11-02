import os
import glob
import requests
from sklearn.feature_extraction.text import TfidfVectorizer
import numpy as np

GROQ_API_KEY = os.environ.get("GROQ_API_KEY")
GROQ_CHAT_URL = "https://api.groq.com/openai/v1/chat/completions"
CHAT_MODEL = "qwen/qwen3.8-27b" 

_vectorizer = None
_docs = []
_tfidf_matrix = None

def _load_knowledge_base():
    global _docs, _vectorizer, _tfidf_matrix
    if _vectorizer is not None: return
    _docs = []
    for path in glob.glob(os.path.join("knowledge_base", "*.md")):
        with open(path, "r", encoding="utf-8") as f:
            text = f.read()
        chunks = [text[i:i+500] for i in range(0, len(text), 500)]
        _docs.extend(chunks)
    if not _docs: return
    _vectorizer = TfidfVectorizer(stop_words="english")
    _tfidf_matrix = _vectorizer.fit_transform(_docs)

def _retrieve(query: str, top_k: int = 3) -> list:
    _load_knowledge_base()
    if _vectorizer is None or not _docs: return []
    q_vec = _vectorizer.transform([query])
    sims = (_tfidf_matrix * q_vec.T).toarray().flatten()
    top_idx = np.argsort(sims)[-top_k:][::-1]
    return [_docs[i] for i in top_idx if sims[i] > 0.01]

# NEW UPDATED PROMPT
SYSTEM_PROMPT = """
You are Ava, the in-app nutritional screening assistant for SuriStanya.
You must answer ONLY using the context provided below.

Rules:
1. Do not use outside knowledge. Do not give medical prescriptions or advise blood tests.
2. Your ultimate goal is to guide the user to complete the 4-image scan.
3. INITIAL STEP: Ask the user if they are experiencing any common symptoms of iron deficiency (e.g., fatigue, paleness, dizziness, brittle nails).
4. AFTER they answer, provide this exact disclaimer: "Please note that SuriStanya is a screening tool, not a medical diagnosis. For medical concerns, consult a doctor."
5. Then, encourage them to use the guided camera to capture their tongue, eye, palm, and nail bed.
6. Keep your answers concise (1-3 sentences).
"""

def get_chat_reply(message: str) -> str:
    if not GROQ_API_KEY:
        return "AI assistant is not configured."
    
    context_chunks = _retrieve(message)
    context = "\n\n---\n\n".join(context_chunks) if context_chunks else "No specific context available. Ask about symptoms."
    
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "system", "content": f"CONTEXT:\n{context}"},
        {"role": "user", "content": message},
    ]
    
    try:
        resp = requests.post(
            GROQ_CHAT_URL,
            headers={"Authorization": f"Bearer {GROQ_API_KEY}", "Content-Type": "application/json"},
            json={"model": CHAT_MODEL, "messages": messages, "temperature": 0.3, "max_tokens": 150},
            timeout=15,
        )
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"].strip()
    except Exception as e:
        print(f"[RAG] Chat failed: {e}")
        return "I'm having trouble connecting right now. Please try again."