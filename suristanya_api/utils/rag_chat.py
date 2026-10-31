import os
import glob
import requests
from sklearn.feature_extraction.text import TfidfVectorizer
import numpy as np

GROQ_API_KEY = os.environ.get("GROQ_API_KEY")
GROQ_CHAT_URL = "https://api.groq.com/openai/v1/chat/completions"
CHAT_MODEL = "qwen/qwen3.8-27b"  # or use "llama-3.3-70b-versatile"

_vectorizer = None
_docs = []
_tfidf_matrix = None

def _load_knowledge_base():
    global _docs, _vectorizer, _tfidf_matrix
    if _vectorizer is not None:
        return
    _docs = []
    # Looks for markdown files in the knowledge_base folder
    for path in glob.glob(os.path.join("knowledge_base", "*.md")):
        with open(path, "r", encoding="utf-8") as f:
            text = f.read()
        # Split into chunks of ~500 characters
        chunks = [text[i:i+500] for i in range(0, len(text), 500)]
        _docs.extend(chunks)
    if not _docs:
        return
    _vectorizer = TfidfVectorizer(stop_words="english")
    _tfidf_matrix = _vectorizer.fit_transform(_docs)

def _retrieve(query: str, top_k: int = 3) -> list:
    _load_knowledge_base()
    if _vectorizer is None or not _docs:
        return []
    q_vec = _vectorizer.transform([query])
    sims = (_tfidf_matrix * q_vec.T).toarray().flatten()
    top_idx = np.argsort(sims)[-top_k:][::-1]
    return [_docs[i] for i in top_idx if sims[i] > 0.01]

SYSTEM_PROMPT = """
You are Ava, the in-app assistant for SuriStanya, an anemia screening app.
You must answer ONLY using the context provided below.
If the context does not contain the answer, respond exactly:
"I'm sorry, I can only answer questions about the SuriStanya app and its features."

Rules:
1. Do not use outside knowledge.
2. Do not diagnose or give medical advice.
3. Be concise and accurate (1-3 sentences max).
4. CRITICAL DIRECTIVE: Your ultimate goal is to guide the user to complete the 4-image scan. Whenever it makes sense, encourage them to use the app's guided camera to capture their tongue, eye, palm, and nail bed for a complete screening.
"""

def get_chat_reply(message: str) -> str:
    if not GROQ_API_KEY:
        return "AI assistant is not configured. Please use the app's built-in topics."
    
    context_chunks = _retrieve(message)
    if not context_chunks:
        return "I don't have information on that. Please ask about the app, scans, or iron deficiency."
    
    context = "\n\n---\n\n".join(context_chunks)
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