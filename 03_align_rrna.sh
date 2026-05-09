#!/bin/bash
# Script: 03_align_rrna.sh

# ===== KONFIGURASI =====
THREADS=4
MAX_JOBS=4
GENOME_DIR="/data/work/star_indices/rRNA"
INPUT_DIR="/data/work/alignment_results/UniVec"
OUTPUT_DIR="/data/work/alignment_results/rRNA2"
TEMP_DIR="/data/work/rRNA"
LOG_DIR="/data/work/logs"

# ===== FUNGSI PROGRESS =====
print_progress() {
local current=$1
local total=$2
local width=50
local percentage=$((current * 100 / total))
local completed=$((current * width / total))
local remaining=$((width - completed))

printf "\r["
printf "%${completed}s" | tr ' ' '='
printf "%${remaining}s" | tr ' ' ' '
printf "] %d%% (%d/%d)" $percentage $current $total
}

# ===== FUNGSI STAR rRNA =====
run_star_rrna() {
local sample=$1
echo "Memproses sampel: $sample"

local R1="${INPUT_DIR}/${sample}_univec_Unmapped.out.mate1"
local R2="${INPUT_DIR}/${sample}_univec_Unmapped.out.mate2"

if [[ ! -f "$R1" ]]; then
echo "❌ ERROR: File R1 tidak ditemukan: $R1"
return 1
fi

if [[ ! -f "$R2" ]]; then
echo "❌ ERROR: File R2 tidak ditemukan: $R2"
return 1
fi

local OUTPUT_PREFIX="${OUTPUT_DIR}/${sample}_rrna_"
local SAMPLE_LOG="${LOG_DIR}/${sample}_rrna_alignment.log"
local TMP_DIR="${TEMP_DIR}/${sample}_tmp"

echo "Memulai alignment rRNA untuk: $sample" > "$SAMPLE_LOG"
echo "File R1: $R1" >> "$SAMPLE_LOG"
echo "File R2: $R2" >> "$SAMPLE_LOG"
echo "Waktu mulai: $(date)" >> "$SAMPLE_LOG"

STAR \
--genomeDir "$GENOME_DIR" \
--readFilesIn "$R1" "$R2" \
--runThreadN "$THREADS" \
--outFileNamePrefix "$OUTPUT_PREFIX" \
--outTmpDir "$TMP_DIR" \
--outSAMtype BAM Unsorted \
--outReadsUnmapped Fastx \
--readFilesCommand "cat" \
--outSAMmultNmax 1 \
--seedPerWindowNmax 20 \
>> "$SAMPLE_LOG" 2>&1

local exit_code=$?

if [ $exit_code -eq 0 ]; then
echo "✅ SUKSES: Sampel $sample selesai diproses"
rm -rf "$TMP_DIR"
return 0
else
echo "❌ ERROR: Gagal memproses sampel $sample (exit code: $exit_code)"
return 1
fi
}

export -f run_star_rrna
export INPUT_DIR OUTPUT_DIR TEMP_DIR LOG_DIR GENOME_DIR THREADS

# ===== MAIN SCRIPT =====
echo "=============================================="
echo " rRNA ALIGNMENT"
echo "=============================================="
echo "Tanggal: $(date)"
echo "Input directory: $INPUT_DIR"
echo "Output directory: $OUTPUT_DIR"
echo "Genome directory: $GENOME_DIR"
echo "Threads per job: $THREADS"
echo "Max concurrent jobs: $MAX_JOBS"
echo "=============================================="

if [[ ! -d "$INPUT_DIR" ]]; then
echo "❌ ERROR: Input directory tidak ditemukan: $INPUT_DIR"
exit 1
fi

if [[ ! -d "$GENOME_DIR" ]]; then
echo "❌ ERROR: Genome directory tidak ditemukan: $GENOME_DIR"
exit 1
fi

cd "$INPUT_DIR"
SAMPLES=()
for unmapped_file in *_univec_Unmapped.out.mate1; do
if [[ -f "$unmapped_file" ]]; then
sample="${unmapped_file%_univec_Unmapped.out.mate1}"
SAMPLES+=("$sample")
fi
done

SAMPLE_COUNT=${#SAMPLES[@]}

if [[ $SAMPLE_COUNT -eq 0 ]]; then
echo "❌ Tidak ditemukan file Unmapped.out.mate1 di $INPUT_DIR"
exit 1
fi

echo "Ditemukan $SAMPLE_COUNT samples untuk diproses"
echo ""

CURRENT=0

if command -v parallel &> /dev/null && [[ $MAX_JOBS -gt 1 ]]; then
echo "Menggunakan GNU Parallel (max jobs: $MAX_JOBS)"
for sample in "${SAMPLES[@]}"; do
((CURRENT++))
print_progress $CURRENT $SAMPLE_COUNT
echo " - Queueing: $sample"
done
echo ""
printf "%s\n" "${SAMPLES[@]}" | parallel -j "$MAX_JOBS" run_star_rrna
else
echo "Menggunakan pemrosesan sequential"
for sample in "${SAMPLES[@]}"; do
((CURRENT++))
print_progress $CURRENT $SAMPLE_COUNT
echo " - Memproses: $sample"
run_star_rrna "$sample"
done
fi

echo ""
echo "=============================================="
echo " rRNA ALIGNMENT SELESAI"
echo "=============================================="
echo "Waktu selesai: $(date)"

SUCCESS_COUNT=0
FAIL_COUNT=0

for sample in "${SAMPLES[@]}"; do
if [[ -f "${OUTPUT_DIR}/${sample}_rrna_Aligned.out.bam" ]]; then
((SUCCESS_COUNT++))
else
((FAIL_COUNT++))
fi
done

echo "Statistik:"
echo "- Berhasil: $SUCCESS_COUNT/$SAMPLE_COUNT"
echo "- Gagal: $FAIL_COUNT/$SAMPLE_COUNT"

if [[ $FAIL_COUNT -gt 0 ]]; then
echo "Samples yang gagal:"
for sample in "${SAMPLES[@]}"; do
if [[ ! -f "${OUTPUT_DIR}/${sample}_rrna_Aligned.out.bam" ]]; then
echo "❌ $sample"
fi
done
fi

echo "Membersihkan temporary files..."
rm -rf "$TEMP_DIR"

echo "=============================================="
