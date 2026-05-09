#!/bin/bash
# Script: 05_kraken2_classify.sh

# ===== KONFIGURASI =====
INPUT_DIR="/data/work/alignment_result/genome"
OUTPUT_DIR="/data/work/kraken_results"
KRAKEN_DB="/data/work/kraken_indices"

cd "$INPUT_DIR"
mate1_files=(*mate1*)

echo "✅ Ditemukan ${#mate1_files[@]} file mate1"

count=0
success=0

for mate1 in "${mate1_files[@]}"; do
((count++))

sample=$(basename "$mate1")
sample=$(echo "$sample" | sed 's/_genome_Unmapped.out.mate1//' | sed 's/.mate1//')
mate2=$(echo "$mate1" | sed 's/mate1/mate2/')

echo ""
echo "--- [$count/${#mate1_files[@]}] $sample ---"
echo "📁 Mate1: $mate1"
echo "📁 Mate2: $mate2"

if [[ ! -f "$mate2" ]]; then
echo "❌ Skip: mate2 tidak ditemukan"
continue
fi

echo "🔬 Running Kraken2..."

kraken2 --db "$KRAKEN_DB" \
--paired "$mate1" "$mate2" \
--threads 4 \
--report "$OUTPUT_DIR/${sample}_report.txt" \
--output "$OUTPUT_DIR/${sample}_output.txt" \
--confidence 0.1 \
--use-names

if [[ $? -eq 0 ]]; then
echo "✅ Berhasil: $sample"
((success++))
else
echo "❌ Gagal: $sample"
fi
done

echo ""
echo "=== SELESAI ==="
echo "📊 Total: ${#mate1_files[@]} samples"
echo "✅ Berhasil: $success samples"
echo "📁 Output: $OUTPUT_DIR"
