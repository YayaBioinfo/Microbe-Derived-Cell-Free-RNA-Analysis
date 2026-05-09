#!/bin/bash
# Script: 04_align_genome.sh

# ===== KONFIGURASI =====
THREADS_PER_JOB=4
MAX_CONCURRENT_JOBS=2
GENOME_DIR="/data/work/star_indices/genome"
INPUT_DIR="/data/work/alignment_results/rRNA2"
OUTPUT_DIR="/data/work/alignment_results/genome"
TEMP_DIR="/data/work/temp/hg38"
LOG_DIR="/data/work/logs"

# ===== VALIDASI =====
cd "$INPUT_DIR" || exit 1

samples=()
for R1_file in *_rrna_Unmapped.out.mate1; do
sample="${R1_file%_rrna_Unmapped.out.mate1}"
samples+=("$sample")
done

echo "=== PARALLEL STAR ALIGNMENT (hg38) ==="
echo "Total samples: ${#samples[@]}"
echo "Concurrent jobs: $MAX_CONCURRENT_JOBS"
echo "Threads per job: $THREADS_PER_JOB"
echo ""

# ===== FUNGSI STAR =====
run_star() {
local sample="$1"
local R1_file="${sample}_rrna_Unmapped.out.mate1"
local R2_file="${sample}_rrna_Unmapped.out.mate2"

echo "[$(date +%H:%M:%S)] 🚀 Memulai: $sample"

STAR \
--genomeDir "$GENOME_DIR" \
--readFilesIn "$R1_file" "$R2_file" \
--runThreadN "$THREADS_PER_JOB" \
--outFileNamePrefix "$OUTPUT_DIR/${sample}_genome_" \
--outTmpDir "$TEMP_DIR/${sample}_tmp" \
--outSAMtype BAM Unsorted \
--outReadsUnmapped Fastx \
--outSAMmultNmax 1 \
--readFilesCommand "cat" \
--seedPerWindowNmax 50 \
> "$LOG_DIR/${sample}_genome_alignment.log" 2>&1

local exit_code=$?

if [[ $exit_code -eq 0 ]]; then
echo "[$(date +%H:%M:%S)] ✅ Selesai: $sample"
else
echo "[$(date +%H:%M:%S)] ❌ Gagal: $sample (exit: $exit_code)"
fi

[[ -d "$TEMP_DIR/${sample}_tmp" ]] && rm -rf "$TEMP_DIR/${sample}_tmp"
}

export -f run_star
export GENOME_DIR INPUT_DIR OUTPUT_DIR TEMP_DIR LOG_DIR THREADS_PER_JOB

echo "📊 Memulai parallel execution..."
printf "%s\n" "${samples[@]}" | xargs -I{} -P "$MAX_CONCURRENT_JOBS" bash -c 'run_star "$@"' _ {}

echo "🎯 SEMUA PROSES PARALLEL SELESAI!"
