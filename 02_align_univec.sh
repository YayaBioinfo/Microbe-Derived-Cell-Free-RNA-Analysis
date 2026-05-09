#!/bin/bash
# Script: 02_align_univec.sh

# ===== KONFIGURASI =====
THREADS=4
MAX_JOBS=2
INPUT_DIR="/data/work/alignment_results/trim"
OUTPUT_DIR="/data/work/alignment_results/UniVec"
TEMP_DIR="/data/work/temp"
LOG_DIR="/data/work/logs"
GENOME_DIR="/data/work/star_indices/UniVec"

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

# ===== MAIN SCRIPT =====
echo "=============================================="
echo " STAR ALIGNMENT TO UNIVEC"
echo "=============================================="
echo "Tanggal: $(date)"
echo "Input directory: $INPUT_DIR"
echo "Output directory: $OUTPUT_DIR"
echo "Threads per job: $THREADS"
echo "Max concurrent jobs: $MAX_JOBS"
echo "=============================================="

cd "$INPUT_DIR"

SAMPLE_COUNT=0
for R1_file in *_R1.fq; do
((SAMPLE_COUNT++))
done

echo "Ditemukan $SAMPLE_COUNT samples untuk diproses"
echo ""

CURRENT=0
for R1_file in *_R1.fq.gz; do
sample="${R1_file%_R1.fq.gz}"
R2_file="${sample}_R2.fq.gz"

((CURRENT++))
print_progress $CURRENT $SAMPLE_COUNT
echo " - Memproses: $sample"

if [[ ! -f "$R2_file" ]]; then
echo "❌ File R2 tidak ditemukan: $R2_file"
continue
fi

OUTPUT_PREFIX="$OUTPUT_DIR/${sample}_univec_"
SAMPLE_LOG="$LOG_DIR/${sample}_univec_alignment.log"
TMP_DIR="$TEMP_DIR/${sample}_univec_tmp"

echo "Memulai alignment untuk: $sample" > "$SAMPLE_LOG"
echo "File R1: $R1_file" >> "$SAMPLE_LOG"
echo "File R2: $R2_file" >> "$SAMPLE_LOG"
echo "Waktu mulai: $(date)" >> "$SAMPLE_LOG"

STAR \
--genomeDir "$GENOME_DIR" \
--readFilesIn "$R1_file" "$R2_file" \
--runThreadN "$THREADS" \
--outFileNamePrefix "$OUTPUT_PREFIX" \
--outTmpDir "$TMP_DIR" \
--outSAMtype BAM Unsorted \
--outReadsUnmapped Fastx \
--outSAMmultNmax 1 \
--readFilesCommand "zcat" \
--seedPerWindowNmax 50 \
--alignEndsType Local \
>> "$SAMPLE_LOG" 2>&1 &

STAR_PID=$!
echo "STAR process PID: $STAR_PID" >> "$SAMPLE_LOG"

while [[ $(jobs -r | wc -l) -ge $MAX_JOBS ]]; do
sleep 10
echo "Menunggu slot proses tersedia ($(jobs -r | wc -l)/$MAX_JOBS berjalan)..."
done
done

echo ""
echo "Menunggu semua proses STAR selesai..."
wait

echo ""
echo "=============================================="
echo " ALIGNMENT SELESAI"
echo "=============================================="
echo "Waktu selesai: $(date)"

echo ""
echo "Membersihkan temporary files..."
rm -rf "$TEMP_DIR"/*_univec_tmp

echo "=============================================="
