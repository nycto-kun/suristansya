# utils/training_logger.py
import json, os, uuid
from datetime import datetime
from pathlib import Path

LOG_DIR = Path(__file__).parent.parent / 'logs'
LOG_DIR.mkdir(exist_ok=True)
PREDICTIONS_LOG = LOG_DIR / 'predictions.jsonl'
MODEL_VERSION = os.environ.get('MODEL_VERSION', 'v1.0-79.4')

def log_prediction(image_bytes, modality_results, fusion_result, user_id=None, image_paths=None) -> dict:
    record = {
        'token': str(uuid.uuid4()),
        'timestamp': datetime.utcnow().isoformat(),
        'model_version': MODEL_VERSION,
        'user_id': user_id,
        'image_paths': image_paths or {},
        'raw_probs': {
            'modalities': {m: r['probabilities'] for m, r in modality_results.items()},
            'fusion': fusion_result['probabilities'],
            'thresholds': {m: r['threshold'] for m, r in modality_results.items()},
        },
        'fusion_label': fusion_result['label'],
        'fusion_confidence': fusion_result['confidence'],
    }
    with PREDICTIONS_LOG.open('a') as f:
        f.write(json.dumps(record) + '\n')
    return record