#!/usr/bin/env python3
"""
Misincorporation Analysis + Machine Learning
"""

import pandas as pd
import numpy as np
import seaborn as sns
import matplotlib.pyplot as plt
from scipy.stats import f_oneway

# ML imports
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split, cross_val_score, StratifiedKFold
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import classification_report, confusion_matrix, ConfusionMatrixDisplay
from sklearn.decomposition import PCA
from sklearn.impute import SimpleImputer
import warnings
warnings.filterwarnings("ignore")

# =========================
# 1. Load Data
# =========================
df_site_sample_base = pd.read_csv("site_sample_base_counts.csv", index_col=0)

metadata = pd.read_csv("metadatamcfrna.txt", sep="\t")
metadata = metadata.set_index("cfRNA_Label")
metadata = metadata.loc[[s for s in metadata.index if s in df_site_sample_base.columns]]
samples = metadata.index.tolist()

print(f"✅ Data loaded: {len(samples)} samples")

# =========================
# 2. Calculate Misincorporation Ratio
# =========================
misincorp_dict = {}
for sample in samples:
    mis_list = []
    for idx, row in df_site_sample_base.iterrows():
        depth = (row.get(f"A_{sample}", 0) + row.get(f"C_{sample}", 0) +
                 row.get(f"G_{sample}", 0) + row.get(f"T_{sample}", 0))
        if depth < 3:
            mis_list.append(np.nan)
            continue
        ref_base = row["ref"]
        col_name = f"{ref_base}_{sample}"
        match_count = row[col_name] if col_name in row.index else 0
        mis = (depth - match_count) / depth
        mis_list.append(mis)
    misincorp_dict[sample] = mis_list

misincorp_df = pd.DataFrame(misincorp_dict, index=df_site_sample_base.index)

# =========================
# 3. Filter Sites
# =========================
depth_df = pd.DataFrame(index=df_site_sample_base.index)
for sample in samples:
    depth_df[sample] = (
        df_site_sample_base.get(f"A_{sample}", 0) +
        df_site_sample_base.get(f"C_{sample}", 0) +
        df_site_sample_base.get(f"G_{sample}", 0) +
        df_site_sample_base.get(f"T_{sample}", 0)
    )

median_depth_per_time = {}
for tp in metadata["timepoint"].unique():
    tp_samples = metadata[metadata["timepoint"] == tp].index.tolist()
    median_depth_per_time[tp] = depth_df[tp_samples].median(axis=1)
median_depth_per_time = pd.DataFrame(median_depth_per_time)

avg_misincorp = misincorp_df.mean(axis=1, skipna=True)
keep_sites = (median_depth_per_time > 5).any(axis=1) & (avg_misincorp > 0.10)
filtered_misincorp_df = misincorp_df.loc[keep_sites]

print(f"✅ Filtered sites: {filtered_misincorp_df.shape[0]} sites x {filtered_misincorp_df.shape[1]} samples")

# =========================
# 4. ANOVA per Site
# =========================
timepoints = sorted(metadata["timepoint"].unique())
anova_results = []
for site in filtered_misincorp_df.index:
    vals_per_tp = [
        filtered_misincorp_df.loc[site, metadata[metadata["timepoint"] == tp].index].dropna()
        for tp in timepoints
    ]
    if all([len(v) >= 2 for v in vals_per_tp]):
        f_val, p_val = f_oneway(*vals_per_tp)
    else:
        p_val = np.nan
    anova_results.append(p_val)

anova_df = pd.DataFrame({
    "site": filtered_misincorp_df.index,
    "p_value_ANOVA": anova_results
})
anova_df.to_csv("differential_methylation_ANOVA_timepoint.csv", index=False)
print("✅ ANOVA saved.")

# =========================
# 5. Heatmap Visualization
# =========================
ordered_samples = metadata.sort_values("timepoint").index.tolist()

plt.figure(figsize=(15, 10))
sns.heatmap(filtered_misincorp_df[ordered_samples].fillna(0), cmap="viridis")
plt.title("Misincorporation Ratio per Timepoint")
plt.xlabel("Sample")
plt.ylabel("Site")
plt.tight_layout()
plt.savefig("misincorp_heatmap_timepoint.png", dpi=300)
plt.close()
print("✅ Heatmap saved.")

# =========================
# 6. MACHINE LEARNING
# =========================
print("\n" + "="*50)
print("  MACHINE LEARNING - TIMEPOINT CLASSIFICATION")
print("="*50)

# --- 6a. Siapkan Feature Matrix ---
# X = samples x sites (transpose dari filtered_misincorp_df)
# y = label timepoint per sample

X_raw = filtered_misincorp_df.T  # shape: (n_samples, n_sites)
y_raw = metadata.loc[X_raw.index, "timepoint"]

print(f"\n📊 Dataset shape: {X_raw.shape}")
print(f"📊 Class distribution:\n{y_raw.value_counts()}")

# --- 6b. Imputasi NaN dengan median ---
imputer = SimpleImputer(strategy="median")
X = imputer.fit_transform(X_raw)
X = pd.DataFrame(X, index=X_raw.index, columns=X_raw.columns)

# --- 6c. Encode label timepoint ke angka ---
le = LabelEncoder()
y = le.fit_transform(y_raw)
print(f"\n✅ Label encoding: {dict(zip(le.classes_, le.transform(le.classes_)))}")

# --- 6d. Train/Test Split ---
# Cek apakah jumlah sampel cukup untuk split
if len(samples) >= 10:
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )
    print(f"\n✅ Train: {len(X_train)} samples | Test: {len(X_test)} samples")

    # --- 6e. Train Random Forest ---
    rf_model = RandomForestClassifier(
        n_estimators=100,
        max_depth=10,
        random_state=42,
        class_weight="balanced"  # handle imbalanced timepoints
    )
    rf_model.fit(X_train, y_train)

    # --- 6f. Evaluasi Model ---
    y_pred = rf_model.predict(X_test)
    print("\n📈 Classification Report:")
    print(classification_report(y_test, y_pred, target_names=le.classes_))

    # Confusion Matrix
    fig, ax = plt.subplots(figsize=(8, 6))
    cm = confusion_matrix(y_test, y_pred)
    disp = ConfusionMatrixDisplay(confusion_matrix=cm, display_labels=le.classes_)
    disp.plot(ax=ax, cmap="Blues")
    plt.title("Confusion Matrix - Timepoint Classification")
    plt.tight_layout()
    plt.savefig("ml_confusion_matrix.png", dpi=300)
    plt.close()
    print("✅ Confusion matrix saved.")

else:
    print("\n⚠️  Sampel terlalu sedikit untuk train/test split.")
    print("   Menggunakan Cross-Validation sebagai gantinya...\n")

# --- 6g. Cross-Validation (lebih robust untuk dataset kecil) ---
print("\n📊 Cross-Validation (5-fold):")

rf_cv = RandomForestClassifier(
    n_estimators=100,
    max_depth=10,
    random_state=42,
    class_weight="balanced"
)

# Gunakan StratifiedKFold supaya proporsi kelas terjaga
n_splits = min(5, len(np.unique(y)))  # sesuaikan fold dengan jumlah kelas
cv = StratifiedKFold(n_splits=n_splits, shuffle=True, random_state=42)

cv_scores = cross_val_score(rf_cv, X, y, cv=cv, scoring="accuracy")
print(f"   Accuracy per fold : {cv_scores.round(3)}")
print(f"   Mean accuracy     : {cv_scores.mean():.3f} ± {cv_scores.std():.3f}")

# Simpan CV results
cv_results = pd.DataFrame({
    "fold": range(1, len(cv_scores) + 1),
    "accuracy": cv_scores
})
cv_results.to_csv("ml_cv_results.csv", index=False)
print("✅ CV results saved.")

# --- 6h. Feature Importance ---
print("\n🔍 Top 20 Most Important Sites:")

rf_cv.fit(X, y)  # fit ulang ke semua data untuk feature importance
feature_importance = pd.DataFrame({
    "site": X.columns,
    "importance": rf_cv.feature_importances_
}).sort_values("importance", ascending=False)

print(feature_importance.head(20).to_string(index=False))
feature_importance.to_csv("ml_feature_importance.csv", index=False)

# Plot feature importance
plt.figure(figsize=(10, 6))
top20 = feature_importance.head(20)
sns.barplot(data=top20, x="importance", y="site", palette="viridis")
plt.title("Top 20 Sites by Feature Importance (Random Forest)")
plt.xlabel("Importance Score")
plt.ylabel("Site")
plt.tight_layout()
plt.savefig("ml_feature_importance.png", dpi=300)
plt.close()
print("✅ Feature importance plot saved.")

# =========================
# 7. PCA Visualisasi
# =========================
print("\n📊 Generating PCA visualization...")

pca = PCA(n_components=2, random_state=42)
X_pca = pca.fit_transform(X)

pca_df = pd.DataFrame({
    "PC1": X_pca[:, 0],
    "PC2": X_pca[:, 1],
    "timepoint": y_raw.values,
    "sample": X_raw.index
})

plt.figure(figsize=(10, 7))
timepoint_colors = sns.color_palette("tab10", len(timepoints))
for i, tp in enumerate(sorted(pca_df["timepoint"].unique())):
    subset = pca_df[pca_df["timepoint"] == tp]
    plt.scatter(subset["PC1"], subset["PC2"],
                label=f"Timepoint {tp}",
                color=timepoint_colors[i],
                s=100, alpha=0.8, edgecolors="black", linewidth=0.5)

plt.xlabel(f"PC1 ({pca.explained_variance_ratio_[0]*100:.1f}% variance)")
plt.ylabel(f"PC2 ({pca.explained_variance_ratio_[1]*100:.1f}% variance)")
plt.title("PCA of Misincorporation Profiles per Sample")
plt.legend(title="Timepoint", bbox_to_anchor=(1.05, 1), loc="upper left")
plt.tight_layout()
plt.savefig("ml_pca_plot.png", dpi=300, bbox_inches="tight")
plt.close()
print("✅ PCA plot saved.")

# =========================
# 8. Summary Output
# =========================
print("\n" + "="*50)
print("  SELESAI — OUTPUT FILES")
print("="*50)
print("📁 misincorp_filtered_matrix.csv    — filtered misincorporation matrix")
print("📁 differential_methylation_ANOVA_timepoint.csv — ANOVA results")
print("📁 misincorp_heatmap_timepoint.png  — heatmap visualisasi")
print("📁 ml_cv_results.csv                — cross-validation scores")
print("📁 ml_feature_importance.csv        — site importance ranking")
print("📁 ml_feature_importance.png        — top 20 sites plot")
print("📁 ml_pca_plot.png                  — PCA per sample")
if len(samples) >= 10:
    print("📁 ml_confusion_matrix.png          — confusion matrix")
print("\n✅ Pipeline complete!")
