# 🧬 cfRNA Metagenomics Pipeline

A modular, parallel bioinformatics pipeline for processing cell-free RNA (cfRNA) sequencing data — from raw reads to functional annotation.

---

## 📋 Pipeline Overview

```
Raw Reads (FASTQ)
      │
      ▼
[1] Quality Control          fastp
      │
      ▼
[2] Vector Depletion          STAR → UniVec
      │
      ▼
[3] rRNA Removal              STAR → rRNA index
      │
      ▼
[4] Human Genome Alignment    STAR → hg38
      │
      ▼
[5] Taxonomic Classification  Kraken2
      │
      ▼
[6] Metagenomic Assembly      MEGAHIT
      │
      ▼
[7] Gene Prediction           Prodigal
      │
      ▼
[8] Functional Annotation     EggNOG-mapper
```

---

## 🗂️ Repository Structure

```
cfRNA-pipeline/
├── scripts/
│   ├── 01_qc_fastp.sh               # Quality control & adapter trimming
│   ├── 02_align_univec.sh            # Vector sequence depletion (UniVec)
│   ├── 03_align_rrna.sh              # rRNA removal
│   ├── 04_align_genome.sh            # Human genome alignment (hg38)
│   ├── 05_kraken2_classify.sh        # Taxonomic classification
│   ├── 06_assembly_annotation.sh     # MEGAHIT assembly + Prodigal gene prediction
│   └── 07_eggnog.sh                  # Functional annotation (EggNOG-mapper)
├── README.md
└── manifest.tsv                      # Sample manifest (see format below)
```

---

## ⚙️ Dependencies

| Tool | Version | Purpose |
|------|---------|---------|
| [fastp](https://github.com/OpenGene/fastp) | ≥0.23 | QC & adapter trimming |
| [STAR](https://github.com/alexdobin/STAR) | ≥2.7 | Alignment (UniVec, rRNA, hg38) |
| [Kraken2](https://github.com/DerrickWood/kraken2) | ≥2.1 | Taxonomic classification |
| [MEGAHIT](https://github.com/voutcn/megahit) | ≥1.2 | De novo assembly |
| [Prodigal](https://github.com/hyattpd/Prodigal) | ≥2.6 | Gene prediction |
| [EggNOG-mapper](https://github.com/eggnogdb/eggnog-mapper) | ≥2.1 | Functional annotation |
| [GNU Parallel](https://www.gnu.org/software/parallel/) | any | Parallel job execution |
| [jq](https://stedolan.github.io/jq/) | any | JSON parsing (fastp summary) |

---

## 📁 Required Reference Databases

Before running, download and index the following:

```bash
# STAR indices (build separately for each reference)
# - /data/work/star_indices/UniVec/
# - /data/work/star_indices/rRNA/
# - /data/work/star_indices/genome/      (hg38)

# Kraken2 database
# - /data/work/kraken_indices/

# EggNOG database
# - /data/work/eggnog/
```

---

## 📄 Manifest Format

The pipeline reads from a `manifest.tsv` file with the following structure:

```
sample_id    /path/to/sample_R1.fastq.gz    /path/to/sample_R2.fastq.gz
```

---

## 🚀 Usage

Each script is self-contained and can be run independently. Edit the `KONFIGURASI` block at the top of each script to set input/output paths and thread counts.

### Step 1 — Quality Control

```bash
bash scripts/01_qc_fastp.sh
```

- Input: paired-end FASTQ from `manifest.tsv`
- Output: trimmed reads in `/data/work/trim/`
- Summary CSV: `/data/work/logs/fastp_summary.csv`

Key parameters:
- `--qualified_quality_phred 5` — base quality threshold
- `--length_required 30` — minimum read length after trimming
- `--detect_adapter_for_pe` — auto-detect PE adapters

---

### Step 2 — Vector Depletion (UniVec)

```bash
bash scripts/02_align_univec.sh
```

- Input: trimmed reads from Step 1
- Output: unmapped reads (non-vector) in `/data/work/alignment_results/UniVec/`

---

### Step 3 — rRNA Removal

```bash
bash scripts/03_align_rrna.sh
```

- Input: UniVec-unmapped reads from Step 2
- Output: non-rRNA reads in `/data/work/alignment_results/rRNA2/`
- Uses GNU Parallel if available; falls back to sequential

---

### Step 4 — Human Genome Alignment

```bash
bash scripts/04_align_genome.sh
```

- Input: rRNA-depleted reads from Step 3
- Output: unmapped (non-human) reads in `/data/work/alignment_results/genome/`

---

### Step 5 — Taxonomic Classification

```bash
bash scripts/05_kraken2_classify.sh
```

- Input: human-unmapped reads from Step 4
- Output: Kraken2 reports in `/data/work/kraken_results/`
- Confidence threshold: `0.1`

---

### Step 6 — Assembly & Gene Prediction

```bash
bash scripts/06_assembly_annotation.sh
```

- Input: human-unmapped reads from Step 4
- MEGAHIT output: contigs in `/data/work/assembly/`
- Prodigal output: predicted proteins in `/data/work/proteins/`
- Runs in parallel (configurable via `PARALLEL_JOBS`)

---

### Step 7 — Functional Annotation

```bash
bash scripts/07_eggnog.sh
```

- Input: `.faa` protein files from Step 6
- Output: EggNOG annotations in `/data/work/eggnog_output/`
- Includes skip logic (won't re-run samples with valid existing annotations)
- Progress monitor runs in background every 30 seconds

---

## ⚡ Parallelization

All scripts support parallel execution via [GNU Parallel](https://www.gnu.org/software/parallel/). If not installed, most scripts fall back to sequential or background (`&`) processing.

Tune these variables per script based on your server:

| Variable | Description |
|----------|-------------|
| `THREADS` / `THREADS_PER_JOB` | CPU cores per individual job |
| `MAX_JOBS` / `PARALLEL_JOBS` | Number of samples running simultaneously |

> Example: `THREADS=4` + `PARALLEL_JOBS=4` = 16 total cores used.

---

## 📊 Output Summary

After running the full pipeline, key outputs include:

| Step | Output File | Description |
|------|-------------|-------------|
| QC | `fastp_summary.csv` | Read counts, Q20/Q30/GC rates per sample |
| Kraken2 | `*_report.txt` | Taxonomic profiles |
| Assembly | `*/final.contigs.fa` | Assembled contigs per sample |
| Prodigal | `*.protein.faa` | Predicted protein sequences |
| EggNOG | `*.emapper.annotations` | COG, KEGG, GO functional annotations |

---

## 🛠️ Configuration Tips

- All scripts use a `# ===== KONFIGURASI =====` block at the top — edit paths there, not inline.
- Scripts include skip logic: if an output file already exists, that sample is skipped (safe to re-run after failures).
- Logs are written per-sample to `/data/work/logs/`.

---

## 👤 Author

Developed as part of a cfRNA microbiome research project.  
Pipeline integrates multi-step depletion, taxonomic profiling, and functional annotation for cell-free metagenomic data.
