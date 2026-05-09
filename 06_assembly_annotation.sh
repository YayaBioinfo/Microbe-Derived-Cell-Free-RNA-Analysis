#!/bin/bash
# Script: 06_assembly_annotation.sh
# MEGAHIT assembly + Prodigal gene prediction

# ===== KONFIGURASI =====
INPUT_DIR="/data/work/alignment_results/genome"
ASSEMBLE_DIR="/data/work/assembly"
PROTEIN_DIR="/data/work/proteins"
THREADS=4
PARALLEL_JOBS=4

mkdir -p "$ASSEMBLE_DIR" "$PROTEIN_DIR"

# ===== FUNGSI =====
process_sample() {
SAMPLE_R1="$1"
SAMPLE_BASE=$(basename "$SAMPLE_R1" "_genome_Unmapped.out.mate1")
SAMPLE_R2="${SAMPLE_R1/_genome_Unmapped.out.mate1/_genome_Unmapped.out.mate2}"

echo "========================================"
echo "Processing: $SAMPLE_BASE"
echo "========================================"

if [[ ! -f "$SAMPLE_R1" ]] || [[ ! -f "$SAMPLE_R2" ]]; then
echo "❌ ERROR: Missing input files for $SAMPLE_BASE"
echo " R1: $SAMPLE_R1"
echo " R2: $SAMPLE_R2"
return 1
fi

rm -rf "${ASSEMBLE_DIR}/${SAMPLE_BASE}_assembly"

echo "➡ MEGAHIT: $SAMPLE_BASE"
megahit -1 "$SAMPLE_R1" -2 "$SAMPLE_R2" \
-o "${ASSEMBLE_DIR}/${SAMPLE_BASE}_assembly" \
--num-cpu-threads "$THREADS"

CONTIGS_FILE="${ASSEMBLE_DIR}/${SAMPLE_BASE}_assembly/final.contigs.fa"
if [[ ! -f "$CONTIGS_FILE" ]]; then
echo "❌ Contigs file not found: $CONTIGS_FILE"
return 1
fi

echo "➡ Prodigal: $SAMPLE_BASE"
OUTPUT_PROTEIN="${PROTEIN_DIR}/${SAMPLE_BASE}.protein.faa"
prodigal -i "$CONTIGS_FILE" -a "$OUTPUT_PROTEIN" -p meta

echo "✅ Finished: $SAMPLE_BASE"
}

export -f process_sample
export INPUT_DIR ASSEMBLE_DIR PROTEIN_DIR THREADS

# ===== MAIN =====
echo "🔍 Finding samples..."

SAMPLE_FILES=($(ls "${INPUT_DIR}"/*_genome_Unmapped.out.mate1 2>/dev/null))

if [[ ${#SAMPLE_FILES[@]} -eq 0 ]]; then
echo "❌ No samples found with pattern: *_genome_Unmapped.out.mate1"
echo "📁 Available files:"
ls -la "$INPUT_DIR"/*.mate1 2>/dev/null | head -10
exit 1
fi

echo "📊 Found ${#SAMPLE_FILES[@]} samples"

if command -v parallel &> /dev/null; then
echo "⚡ PARALLEL MODE: $PARALLEL_JOBS parallel jobs"
printf "%s\n" "${SAMPLE_FILES[@]}" | parallel -j "$PARALLEL_JOBS" --eta 'process_sample {}'
else
echo "🔄 SEQUENTIAL MODE"
for SAMPLE in "${SAMPLE_FILES[@]}"; do
process_sample "$SAMPLE"
done
fi

echo "🎉 ALL SAMPLES COMPLETED"
