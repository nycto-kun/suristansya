# xgb_utils.py
# Shared helpers for native-XGBoost training with per-iteration metrics,
# plus feature engineering + fusion pipeline for multi-modal stacking.

import numpy as np
import xgboost as xgb
from sklearn.metrics import precision_score, recall_score, f1_score, accuracy_score
from collections import Counter


class XGBWrapper:
    """Sklearn-style wrapper around a native xgboost Booster."""
    def __init__(self, booster, threshold=0.5):
        self.booster = booster
        self.threshold = threshold
        self.best_iteration = getattr(booster, 'best_iteration', None)

    def _predict_raw(self, X):
        dmat = xgb.DMatrix(X)
        if self.best_iteration is not None:
            return self.booster.predict(dmat, iteration_range=(0, self.best_iteration + 1))
        return self.booster.predict(dmat)

    def predict_proba(self, X):
        p = self._predict_raw(X)
        return np.column_stack([1.0 - p, p])

    def predict(self, X):
        return (self._predict_raw(X) >= self.threshold).astype(int)

    def get_params(self, deep=True):
        return dict(self.booster.attributes())


class XGBPerIterationMetricsCallback(xgb.callback.TrainingCallback):
    """Records precision/recall/f1/accuracy/support per boosting round."""
    def __init__(self, X_val, y_val, threshold=0.5):
        super().__init__()
        if isinstance(X_val, xgb.DMatrix):
            self._dval = X_val
            self.X_val = None
        else:
            self.X_val = np.asarray(X_val)
            self._dval = None
        self.y_val = np.asarray(y_val).flatten().astype(int)
        self.threshold = threshold
        self.metrics = {
            'iteration': [],
            'precision': [], 'recall': [], 'f1': [], 'accuracy': [],
            'support_non_anemic': [], 'support_anemic': []
        }

    def after_iteration(self, model, epoch, evals_log):
        if self._dval is None:
            self._dval = xgb.DMatrix(self.X_val)
        preds = model.predict(self._dval, iteration_range=(0, epoch + 1))
        y_pred = (preds >= self.threshold).astype(int)
        self.metrics['iteration'].append(int(epoch + 1))
        self.metrics['precision'].append(float(precision_score(self.y_val, y_pred, zero_division=0)))
        self.metrics['recall'].append(float(recall_score(self.y_val, y_pred, zero_division=0)))
        self.metrics['f1'].append(float(f1_score(self.y_val, y_pred, zero_division=0)))
        self.metrics['accuracy'].append(float(accuracy_score(self.y_val, y_pred)))
        self.metrics['support_non_anemic'].append(int(np.sum(self.y_val == 0)))
        self.metrics['support_anemic'].append(int(np.sum(self.y_val == 1)))
        return False


# =============================================================
# FEATURE ENGINEERING FOR FUSION
# =============================================================

def engineer_features(X_probs, eps=1e-7):
    """Expand the 8-dim probability vector into a rich feature set.

    Input:  (N, 8) = [p0_m1, p1_m1, p0_m2, p1_m2, p0_m3, p1_m3, p0_m4, p1_m4]
    Output: (N, 38)
    """
    X = np.asarray(X_probs, dtype=np.float64)
    p0 = X[:, 0::2]                 # (N, 4)  non-anemic prob per modality
    p1 = X[:, 1::2]                 # (N, 4)  anemic prob per modality

    log_odds = np.log((p1 + eps) / (p0 + eps))
    entropy = -(p1 * np.log(p1 + eps) + p0 * np.log(p0 + eps))
    confidence = np.abs(p1 - 0.5) * 2.0
    preds = (p1 >= 0.5).astype(np.float64)

    mean_p1 = p1.mean(axis=1, keepdims=True)
    std_p1 = p1.std(axis=1, keepdims=True)
    max_p1 = p1.max(axis=1, keepdims=True)
    min_p1 = p1.min(axis=1, keepdims=True)
    median_p1 = np.median(p1, axis=1, keepdims=True)

    vote_sum = preds.sum(axis=1, keepdims=True)
    log_odds_sum = log_odds.sum(axis=1, keepdims=True)
    log_odds_mean = log_odds.mean(axis=1, keepdims=True)
    entropy_mean = entropy.mean(axis=1, keepdims=True)
    conf_mean = confidence.mean(axis=1, keepdims=True)
    conf_max = confidence.max(axis=1, keepdims=True)

    w_vote = (p1 * confidence).sum(axis=1, keepdims=True) / (confidence.sum(axis=1, keepdims=True) + eps)

    odds = p1 / (p0 + eps)
    log_odds_prod = np.log(odds + eps).sum(axis=1, keepdims=True)

    # Max agreement (mode count across the 4 predicted classes)
    agree_count = np.zeros((X.shape[0], 1))
    for i in range(X.shape[0]):
        c = Counter(preds[i].astype(int))
        if c:
            agree_count[i, 0] = c.most_common(1)[0][1]

    feats = np.hstack([
        p0, p1,                                                    # 8
        log_odds, entropy, confidence, preds,                      # 16
        mean_p1, std_p1, max_p1, min_p1, median_p1,                # 5
        vote_sum, log_odds_sum, log_odds_mean,                     # 3
        entropy_mean, conf_mean, conf_max,                         # 3
        w_vote, log_odds_prod, agree_count,                        # 3
    ])
    return feats.astype(np.float32)


# =============================================================
# FUSION PIPELINE (bundles feature engineering + trained model)
# =============================================================

class FusionPipeline:
    """Sklearn-style wrapper so downstream code can call
    `pipeline.predict_proba(X_raw_8dim)` directly."""

    def __init__(self, model, threshold=0.5):
        self.model = model
        self.threshold = threshold

    def predict_proba(self, X_raw):
        X_eng = engineer_features(X_raw)
        return self.model.predict_proba(X_eng)

    def predict(self, X_raw):
        return (self.predict_proba(X_raw)[:, 1] >= self.threshold).astype(int)