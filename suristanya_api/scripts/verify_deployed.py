import os
import sys
import json
import numpy as np
import joblib

# ── CRITICAL: add project root to sys.path so xgb_utils can be imported ──
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

import xgb_utils  # noqa — force import before unpickling
from keras.models import load_model
from keras.utils import load_img, img_to_array
from sklearn.metrics import (accuracy_score, precision_score, recall_score,
                              f1_score, balanced_accuracy_score, confusion_matrix,
                              classification_report)

MODELS = os.path.join(PROJECT_ROOT, 'models')
DATASETS = os.path.join(PROJECT_ROOT, 'DATASETS')
IMG_SIZE = (224, 224)
CLASS_NAMES = ['Non_Anemic', 'Anemic']

MODALITIES = {
    'tongue': ('TONGUES', 'Tongues(main)'),
    'eye':    ('EYES', 'Eyes(main)'),
    'nail':   ('NAIL_BEDS', 'Fingernails(main)'),
    'palm':   ('PALMS', 'Palms(main)'),
}


def _mpath(modality, suffix):
    for p in [os.path.join(MODELS, f'{modality}_{suffix}'),
              os.path.join(MODELS, modality, f'{modality}_{suffix}')]:
        if os.path.exists(p):
            return p
    raise FileNotFoundError(f'{modality}_{suffix} not found')


def _load_pickle(path):
    try:
        with open(path, 'rb') as f:
            import pickle
            return pickle.load(f)
    except Exception:
        return joblib.load(path)


def find_image_folder(modality):
    top, sub = MODALITIES[modality]
    for candidate in ['Testing', 'Training']:
        d = os.path.join(DATASETS, top, sub, candidate)
        if os.path.isdir(d):
            # Verify it has subfolders
            if any(os.path.isdir(os.path.join(d, cn)) for cn in CLASS_NAMES):
                return d
    return None


def predict_modality(modality):
    fm = load_model(_mpath(modality, 'feature_model.h5'), compile=False)
    sc = _load_pickle(_mpath(modality, 'scaler.pkl'))
    cl = _load_pickle(_mpath(modality, 'classifier.pkl'))
    thr = _load_pickle(_mpath(modality, 'threshold.pkl'))
    threshold = float(thr.get('threshold', 0.5)) if isinstance(thr, dict) else float(thr)

    test_dir = find_image_folder(modality)
    if not test_dir:
        raise FileNotFoundError(f'No image folder found for {modality}')

    feats, labels = [], []
    for ci, cn in enumerate(CLASS_NAMES):
        d = os.path.join(test_dir, cn)
        if not os.path.isdir(d):
            print(f'  ⚠️  Missing class folder: {d}')
            continue
        for f in os.listdir(d):
            if f.endswith(('.jpg', '.png', '.jpeg')):
                try:
                    img = load_img(os.path.join(d, f), target_size=IMG_SIZE)
                    arr = img_to_array(img) / 255.0
                    feat = fm.predict(np.expand_dims(arr, 0), verbose=0)
                    if feat.ndim == 4:
                        feat = np.mean(feat, axis=(1, 2))
                    feats.append(feat.reshape(-1))
                    labels.append(ci)
                except Exception:
                    pass

    if not feats:
        raise ValueError(f'No images loaded for {modality} — check DATASETS path')

    X = np.array(feats)
    y = np.array(labels)
    probs = cl.predict_proba(sc.transform(X))
    preds = (probs[:, 1] >= threshold).astype(int)

    return {
        'modality': modality, 'n_samples': len(y), 'threshold': threshold,
        'accuracy': float(accuracy_score(y, preds)),
        'balanced_accuracy': float(balanced_accuracy_score(y, preds)),
        'precision': float(precision_score(y, preds, zero_division=0)),
        'recall': float(recall_score(y, preds, zero_division=0)),
        'f1': float(f1_score(y, preds, zero_division=0)),
        'confusion_matrix': confusion_matrix(y, preds).tolist(),
        'classification_report': classification_report(y, preds, target_names=CLASS_NAMES, output_dict=True),
        'probs': probs.tolist(), 'labels': y.tolist(),
    }


def evaluate_fusion(modality_data):
    for p in [os.path.join(MODELS, 'fusion_model.pkl'),
              os.path.join(MODELS, 'fusion', 'fusion_model.pkl')]:
        if os.path.exists(p):
            fusion = _load_pickle(p)
            break
    else:
        print('❌ No fusion_model.pkl found')
        return None

    min_len = min(len(d['probs']) for d in modality_data.values())
    vectors, y_true = [], []
    for i in range(min_len):
        vec = []
        for mod in ['tongue', 'eye', 'nail', 'palm']:
            probs = modality_data.get(mod, {}).get('probs', [])
            vec.extend(probs[i] if i < len(probs) else [0.5, 0.5])
        vectors.append(vec)
        y_true.append(modality_data['tongue']['labels'][i])

    X = np.array(vectors, dtype=np.float32)
    y = np.array(y_true)
    probs = fusion.predict_proba(X)
    preds = (probs[:, 1] >= fusion.threshold).astype(int)

    return {
        'n_samples': min_len, 'threshold': float(fusion.threshold),
        'accuracy': float(accuracy_score(y, preds)),
        'balanced_accuracy': float(balanced_accuracy_score(y, preds)),
        'precision': float(precision_score(y, preds, zero_division=0)),
        'recall': float(recall_score(y, preds, zero_division=0)),
        'f1': float(f1_score(y, preds, zero_division=0)),
        'confusion_matrix': confusion_matrix(y, preds).tolist(),
        'classification_report': classification_report(y, preds, target_names=CLASS_NAMES, output_dict=True),
    }


if __name__ == '__main__':
    print('=' * 70)
    print('VERIFYING DEPLOYED MODELS (read-only)')
    print('=' * 70)
    results, modality_data = {}, {}
    for modality in MODALITIES:
        print(f'\nEvaluating {modality}...')
        try:
            r = predict_modality(modality)
            modality_data[modality] = r
            print(f'  ✅ n={r["n_samples"]} acc={r["accuracy"]:.4f} recall={r["recall"]:.4f} f1={r["f1"]:.4f}')
            results[modality] = {k: v for k, v in r.items() if k not in ('probs', 'labels')}
        except Exception as e:
            print(f'  ❌ {e}')

    print('\nEvaluating fusion...')
    try:
        fr = evaluate_fusion(modality_data)
        if fr:
            print(f'  ✅ n={fr["n_samples"]} acc={fr["accuracy"]:.4f} recall={fr["recall"]:.4f} bal={fr["balanced_accuracy"]:.4f}')
            results['fusion'] = fr
    except Exception as e:
        import traceback; traceback.print_exc()

    with open('deployed_model_metrics.json', 'w') as f:
        json.dump(results, f, indent=2)
    print('\n✅ Saved: deployed_model_metrics.json')