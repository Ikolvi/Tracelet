//! Crash-detection ML model — a portable random-forest tree-walker (#183).
//!
//! Runs a RandomForest crash classifier on-device with **no ML runtime** and a
//! tiny memory footprint. The model is shipped as the dependency-free JSON the
//! training notebook emits:
//!
//! ```json
//! { "features": ["peak_g","dv","gyro_peak_dps","speed_max","mean_g"],
//!   "classes": [0, 1],
//!   "trees": [ { "feature":[...], "threshold":[...],
//!               "children_left":[...], "children_right":[...],
//!               "value":[[c0,c1], ...] }, ... ] }
//! ```
//!
//! At load we parse that into a **compact flat representation** (≈20 bytes/node,
//! `f32`, leaf probability pre-computed) so a 150-tree/depth-12 forest is ~4–5 MB
//! resident instead of the ~13 MB JSON. Inference walks each tree and averages
//! the leaf probabilities — exactly reproducing scikit-learn's `predict_proba`.
//!
//! The model is an **opt-in, downloaded** add-on (it is never embedded), so the
//! base SDK size is unchanged. Loading is gated by the host so it only lives in
//! memory while crash detection is active.
//!
//! Loading rejects any model whose declared features are not in
//! [`SUPPORTED_FEATURES`] (#309) — see that constant for why an unrecognised
//! name is far worse than a load failure.

use crate::error::TraceletError;
use aes_gcm::{
    aead::{generic_array::GenericArray, Aead, KeyInit},
    Aes256Gcm, Nonce,
};
use serde::Deserialize;
use std::sync::Mutex;

/// One decision-tree node in the compact in-memory form.
///
/// `feature < 0` marks a leaf; then `proba` is the pre-normalized P(class==1) at
/// that leaf and `left`/`right` are unused.
#[derive(Clone, Copy)]
struct Node {
    feature: i32,
    threshold: f32,
    left: i32,
    right: i32,
    proba: f32,
}

/// The forest: each tree is a flat `Vec<Node>` indexed by node id (root = 0).
struct Forest {
    feature_names: Vec<String>,
    trees: Vec<Vec<Node>>,
}

/// The feature names the SDK can actually supply at inference time, in the units
/// the model is trained on (`peak_g`/`mean_g` in g, `gyro_peak_dps` in deg/s,
/// `speed_max`/`dv` in km/h).
///
/// A model is only accepted if every name it declares is in this set (#309).
/// The hosts build the feature vector by looking each declared name up in a
/// `byName` map and defaulting misses to `0.0`, so an unrecognised name is not a
/// loud failure — it feeds the model a zero. A model trained on differently
/// named features (e.g. the `accel_g`/`gyro_dps`/`speed_kmh` triple an older
/// training notebook emitted) would therefore score an all-zero vector — "0 g,
/// 0 deg/s, 0 km/h" — as firmly not-a-crash on every window. And because a
/// probability of `0.0` still satisfies `crash_proba >= 0.0`, the detector stays
/// in ML **Replace** mode and never falls back to the g-threshold rule: crash
/// detection would be silently dead while the SDK reported the model as ready.
pub const SUPPORTED_FEATURES: [&str; 5] =
    ["peak_g", "mean_g", "gyro_peak_dps", "speed_max", "dv"];

// ── Raw JSON shapes (parsed once, then discarded for the compact form) ────────

#[derive(Deserialize)]
struct RawTree {
    feature: Vec<i64>,
    threshold: Vec<f64>,
    children_left: Vec<i64>,
    children_right: Vec<i64>,
    /// Per-node class counts: `value[node] = [count_class0, count_class1, ...]`.
    value: Vec<Vec<f64>>,
}

#[derive(Deserialize)]
struct RawForest {
    #[serde(default)]
    features: Vec<String>,
    classes: Vec<i64>,
    trees: Vec<RawTree>,
}

/// On-device crash classifier (random-forest tree-walker).
#[derive(uniffi::Object)]
pub struct CrashModel {
    forest: Mutex<Forest>,
}

#[uniffi::export]
impl CrashModel {
    /// Loads a model from the training-notebook JSON. Returns a `Config` error if
    /// the JSON is malformed, the positive class (`1`) is absent, or any declared
    /// feature is outside [`SUPPORTED_FEATURES`].
    #[uniffi::constructor]
    pub fn from_json(json: String) -> Result<CrashModel, TraceletError> {
        let raw: RawForest = serde_json::from_str(&json)
            .map_err(|e| TraceletError::Config(format!("crash model parse: {e}")))?;
        Ok(CrashModel {
            forest: Mutex::new(compile(raw)?),
        })
    }

    /// Loads from an **AES-256-GCM encrypted** model blob (#183 — keeps the paid
    /// model from being grabbed off a plain URL/cache). The blob layout matches
    /// the SDK's encrypted-payload format: `[0x01][nonce:12][ciphertext]`.
    ///
    /// `key` is a **32-byte** key supplied at runtime by the host — it is never
    /// hardcoded in this (open-source) repo. Returns a `Config` error on a bad
    /// key/blob (wrong key, tampered data) or malformed decrypted JSON.
    #[uniffi::constructor]
    pub fn from_encrypted(blob: Vec<u8>, key: Vec<u8>) -> Result<CrashModel, TraceletError> {
        if key.len() != 32 {
            return Err(TraceletError::Config(
                "crash model: key must be 32 bytes".into(),
            ));
        }
        if blob.len() < 13 || blob[0] != 0x01 {
            return Err(TraceletError::Config(
                "crash model: bad encrypted blob header".into(),
            ));
        }
        let cipher = Aes256Gcm::new(GenericArray::from_slice(&key));
        let nonce = Nonce::from_slice(&blob[1..13]);
        let plaintext = cipher
            .decrypt(nonce, &blob[13..])
            .map_err(|_| TraceletError::Config("crash model: decryption failed".into()))?;
        let json = String::from_utf8(plaintext)
            .map_err(|_| TraceletError::Config("crash model: decrypted bytes not UTF-8".into()))?;
        Self::from_json(json)
    }

    /// Ordered feature names the model expects (the host must supply `predict`
    /// values in this exact order).
    pub fn feature_names(&self) -> Vec<String> {
        self.forest.lock().unwrap().feature_names.clone()
    }

    /// Number of trees (diagnostics).
    pub fn tree_count(&self) -> u32 {
        self.forest.lock().unwrap().trees.len() as u32
    }

    /// Probability of a crash (class `1`) in `[0, 1]` for one feature vector,
    /// averaged across all trees. `features` must be in [`feature_names`] order;
    /// a wrong length returns `0.0` (never panics on the hot path).
    pub fn predict_proba(&self, features: Vec<f64>) -> f64 {
        let forest = self.forest.lock().unwrap();
        if forest.trees.is_empty() {
            return 0.0;
        }
        let mut sum = 0.0f64;
        for tree in &forest.trees {
            sum += walk(tree, &features) as f64;
        }
        sum / forest.trees.len() as f64
    }

    /// Convenience: `predict_proba(features) >= threshold`.
    pub fn is_crash(&self, features: Vec<f64>, threshold: f64) -> bool {
        self.predict_proba(features) >= threshold
    }
}

/// Walks one tree to its leaf and returns the leaf's P(class==1).
fn walk(tree: &[Node], x: &[f64]) -> f32 {
    if tree.is_empty() {
        return 0.0;
    }
    let mut i = 0usize;
    loop {
        let n = tree[i];
        if n.feature < 0 {
            return n.proba; // leaf
        }
        let fi = n.feature as usize;
        // Out-of-range feature index → treat as missing (go left); never panic.
        let go_left = x.get(fi).map(|&v| v <= n.threshold as f64).unwrap_or(true);
        let next = if go_left { n.left } else { n.right };
        if next < 0 {
            return n.proba; // defensive: malformed child → use node proba
        }
        i = next as usize;
    }
}

/// Compiles the raw JSON forest into the compact flat form, pre-computing each
/// leaf's normalized P(class==1).
fn compile(raw: RawForest) -> Result<Forest, TraceletError> {
    // Reject a model the host cannot actually feed (#309). Checked before
    // anything else so a mis-exported model fails at load — where the caller
    // falls back to the rule engine — rather than scoring zeros forever.
    if raw.features.is_empty() {
        return Err(TraceletError::Config(
            "crash model: no feature names declared — cannot map the host's features".into(),
        ));
    }
    if let Some(unknown) = raw
        .features
        .iter()
        .find(|f| !SUPPORTED_FEATURES.contains(&f.as_str()))
    {
        return Err(TraceletError::Config(format!(
            "crash model: unsupported feature '{unknown}' (supported: {})",
            SUPPORTED_FEATURES.join(", ")
        )));
    }

    // Index of the positive ("crash") class == 1 in the model's class list.
    let class_idx = raw
        .classes
        .iter()
        .position(|&c| c == 1)
        .ok_or_else(|| TraceletError::Config("crash model: positive class 1 not found".into()))?;

    let mut trees = Vec::with_capacity(raw.trees.len());
    for t in raw.trees {
        let n = t.feature.len();
        if t.threshold.len() != n
            || t.children_left.len() != n
            || t.children_right.len() != n
            || t.value.len() != n
        {
            return Err(TraceletError::Config(
                "crash model: inconsistent tree array lengths".into(),
            ));
        }
        let mut nodes = Vec::with_capacity(n);
        for i in 0..n {
            let is_leaf = t.children_left[i] == -1;
            let proba = if is_leaf {
                let counts = &t.value[i];
                let total: f64 = counts.iter().sum();
                if total > 0.0 {
                    (counts.get(class_idx).copied().unwrap_or(0.0) / total) as f32
                } else {
                    0.0
                }
            } else {
                0.0
            };
            nodes.push(Node {
                feature: if is_leaf { -1 } else { t.feature[i] as i32 },
                threshold: t.threshold[i] as f32,
                left: t.children_left[i] as i32,
                right: t.children_right[i] as i32,
                proba,
            });
        }
        trees.push(nodes);
    }

    Ok(Forest {
        feature_names: raw.features,
        trees,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    // A 2-tree forest over 1 feature, hand-checkable.
    // Tree A: if x0 <= 2.0 -> leaf [9,1] (P1=0.1) else leaf [1,9] (P1=0.9)
    // Tree B: if x0 <= 5.0 -> leaf [6,4] (P1=0.4) else leaf [0,10] (P1=1.0)
    const FIXTURE: &str = r#"{
      "features": ["peak_g"],
      "classes": [0, 1],
      "trees": [
        {"feature":[0,-2,-2],"threshold":[2.0,-2.0,-2.0],
         "children_left":[1,-1,-1],"children_right":[2,-1,-1],
         "value":[[10,10],[9,1],[1,9]]},
        {"feature":[0,-2,-2],"threshold":[5.0,-2.0,-2.0],
         "children_left":[1,-1,-1],"children_right":[2,-1,-1],
         "value":[[6,14],[6,4],[0,10]]}
      ]
    }"#;

    #[test]
    fn parses_and_reports_metadata() {
        let m = CrashModel::from_json(FIXTURE.into()).unwrap();
        assert_eq!(m.feature_names(), vec!["peak_g".to_string()]);
        assert_eq!(m.tree_count(), 2);
    }

    #[test]
    fn averages_leaf_probabilities_across_trees() {
        let m = CrashModel::from_json(FIXTURE.into()).unwrap();
        // x0 = 1.0 -> A: <=2 -> 0.1 ; B: <=5 -> 0.4 ; avg = 0.25
        assert!((m.predict_proba(vec![1.0]) - 0.25).abs() < 1e-6);
        // x0 = 9.0 -> A: >2 -> 0.9 ; B: >5 -> 1.0 ; avg = 0.95
        assert!((m.predict_proba(vec![9.0]) - 0.95).abs() < 1e-6);
        // x0 = 3.0 -> A: >2 -> 0.9 ; B: <=5 -> 0.4 ; avg = 0.65
        assert!((m.predict_proba(vec![3.0]) - 0.65).abs() < 1e-6);
    }

    #[test]
    fn is_crash_applies_threshold() {
        let m = CrashModel::from_json(FIXTURE.into()).unwrap();
        assert!(m.is_crash(vec![9.0], 0.5)); // 0.95 >= 0.5
        assert!(!m.is_crash(vec![1.0], 0.5)); // 0.25 < 0.5
    }

    #[test]
    fn missing_class_one_errors() {
        let bad = r#"{"features":["peak_g"],"classes":[0,2],"trees":[]}"#;
        assert!(CrashModel::from_json(bad.into()).is_err());
    }

    // ── #309: a model the host cannot feed must be rejected at load ──

    #[test]
    fn unsupported_feature_names_are_rejected() {
        // The `accel_g`/`gyro_dps`/`speed_kmh` triple an older training notebook
        // emitted: the host has no such names, so every feature would resolve to
        // 0.0 and the model would score "not a crash" on every window — while
        // still holding the detector in ML Replace mode, silently suppressing the
        // g-threshold rule. Loading must fail so the caller falls back.
        let bad = r#"{"features":["accel_g","gyro_dps","speed_kmh"],"classes":[0,1],
                      "trees":[{"feature":[-2],"threshold":[-2.0],
                                "children_left":[-1],"children_right":[-1],
                                "value":[[1,1]]}]}"#;
        let Err(err) = CrashModel::from_json(bad.into()) else {
            panic!("a model with unsupported feature names must not load");
        };
        assert!(
            format!("{err}").contains("accel_g"),
            "error should name the offending feature, got: {err}"
        );
    }

    #[test]
    fn one_unsupported_feature_among_valid_ones_is_rejected() {
        let bad = r#"{"features":["peak_g","speed_kmh"],"classes":[0,1],
                      "trees":[{"feature":[-2],"threshold":[-2.0],
                                "children_left":[-1],"children_right":[-1],
                                "value":[[1,1]]}]}"#;
        assert!(CrashModel::from_json(bad.into()).is_err());
    }

    #[test]
    fn missing_features_key_is_rejected() {
        // `features` is `#[serde(default)]`, so a model exported without it used
        // to parse into an empty name list — the host then built an EMPTY feature
        // vector and every tree took the all-left path.
        let bad = r#"{"classes":[0,1],
                      "trees":[{"feature":[-2],"threshold":[-2.0],
                                "children_left":[-1],"children_right":[-1],
                                "value":[[1,1]]}]}"#;
        assert!(CrashModel::from_json(bad.into()).is_err());
    }

    #[test]
    fn every_supported_feature_name_loads() {
        let names = SUPPORTED_FEATURES
            .iter()
            .map(|f| format!("\"{f}\""))
            .collect::<Vec<_>>()
            .join(",");
        let json = format!(
            r#"{{"features":[{names}],"classes":[0,1],
                 "trees":[{{"feature":[-2],"threshold":[-2.0],
                            "children_left":[-1],"children_right":[-1],
                            "value":[[1,1]]}}]}}"#
        );
        let m = CrashModel::from_json(json).unwrap();
        assert_eq!(m.feature_names().len(), SUPPORTED_FEATURES.len());
    }

    #[test]
    fn wrong_feature_count_does_not_panic() {
        let m = CrashModel::from_json(FIXTURE.into()).unwrap();
        // Empty / wrong-length vector must not panic; goes left at the root.
        let _ = m.predict_proba(vec![]);
    }

    #[test]
    fn malformed_json_errors() {
        assert!(CrashModel::from_json("not json".into()).is_err());
    }

    fn encrypt(plaintext: &[u8], key: &[u8; 32]) -> Vec<u8> {
        use aes_gcm::aead::OsRng;
        use aes_gcm::aead::rand_core::RngCore;
        let cipher = Aes256Gcm::new(GenericArray::from_slice(key));
        let mut nonce_bytes = [0u8; 12];
        OsRng.fill_bytes(&mut nonce_bytes);
        let ct = cipher
            .encrypt(Nonce::from_slice(&nonce_bytes), plaintext)
            .unwrap();
        let mut out = vec![0x01u8];
        out.extend_from_slice(&nonce_bytes);
        out.extend_from_slice(&ct);
        out
    }

    #[test]
    fn encrypted_round_trip_matches_plaintext() {
        let key = [7u8; 32];
        let blob = encrypt(FIXTURE.as_bytes(), &key);
        let m = CrashModel::from_encrypted(blob, key.to_vec()).unwrap();
        assert_eq!(m.tree_count(), 2);
        assert!((m.predict_proba(vec![3.0]) - 0.65).abs() < 1e-6);
    }

    #[test]
    fn wrong_key_fails_to_decrypt() {
        let blob = encrypt(FIXTURE.as_bytes(), &[7u8; 32]);
        assert!(CrashModel::from_encrypted(blob, vec![9u8; 32]).is_err());
    }

    #[test]
    fn bad_key_length_errors() {
        assert!(CrashModel::from_encrypted(vec![0x01; 20], vec![1u8; 16]).is_err());
    }
}
