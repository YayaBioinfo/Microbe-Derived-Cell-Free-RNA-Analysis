#!/bin/bash
# Script: 01_qc_fastp.sh
# Analisis FASTP dengan konfigurasi sederhana

# ===== KONFIGURASI =====
MANIFEST="manifest.tsv"
OUTPUT_DIR="/data/work/trim"
LOG_DIR="/data/work/logs"
THREADS=4
MAX_JOBS=2

# ===== SETUP =====
echo "Menyiapkan direktori..."
mkdir -p "$OUTPUT_DIR"
mkdir -p "$LOG_DIR"

# ===== FUNGSI =====
extract_paths() {
awk -F'\t' '
NR==1 {next}
{
for(i=2; i<=NF; i++) {
if($i ~ /^\//) {
if(forward == "") {
forward = $i
} else {
reverse = $i
break
}
}
}
print $1 "\t" forward "\t" reverse
forward = ""; reverse = ""
}' "$MANIFEST"
}

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
echo " FASTP PROCESSING - SIMPLE"
echo "=============================================="
echo "Tanggal: $(date)"
echo "Threads: $THREADS"
echo "Max Jobs: $MAX_JOBS"
echo "=============================================="

# Ekstrak daftar sampel
echo "Mengekstrak daftar sampel..."
TEMP_FILE=$(mktemp)
extract_paths > "$TEMP_FILE"

SAMPLE_COUNT=0
while IFS=$'\t' read -r sample_id forward_path reverse_path; do
SAMPLE_LIST[$SAMPLE_COUNT]="$sample_id"
FORWARD_LIST[$SAMPLE_COUNT]="$forward_path"
REVERSE_LIST[$SAMPLE_COUNT]="$reverse_path"
((SAMPLE_COUNT++))
done < "$TEMP_FILE"
rm -f "$TEMP_FILE"

echo "Ditemukan $SAMPLE_COUNT sampel untuk diproses"
echo ""

# Proses setiap sampel
CURRENT=0
for ((i=0; i<SAMPLE_COUNT; i++)); do
sample_id="${SAMPLE_LIST[$i]}"
forward_path="${FORWARD_LIST[$i]}"
reverse_path="${REVERSE_LIST[$i]}"

((CURRENT++))
print_progress $CURRENT $SAMPLE_COUNT
echo " - Memproses: $sample_id"

R1_OUT="$OUTPUT_DIR/${sample_id}_R1.fq.gz"
R2_OUT="$OUTPUT_DIR/${sample_id}_R2.fq.gz"
JSON_REPORT="$OUTPUT_DIR/${sample_id}_fastp.json"
HTML_REPORT="$OUTPUT_DIR/${sample_id}_fastp.html"
SAMPLE_LOG="$LOG_DIR/${sample_id}_fastp.log"

fastp \
-i "$forward_path" \
-I "$reverse_path" \
-o "$R1_OUT" \
-O "$R2_OUT" \
--qualified_quality_phred 5 \
--n_base_limit 15 \
--unqualified_percent_limit 50 \
--length_required 30 \
--trim_poly_x \
--detect_adapter_for_pe \
--trim_poly_g \
--thread "$THREADS" \
--json "$JSON_REPORT" \
--html "$HTML_REPORT" \
> "$SAMPLE_LOG" 2>&1 &

while [ $(jobs -r | wc -l) -ge $MAX_JOBS ]; do
sleep 5
print_progress $CURRENT $SAMPLE_COUNT
echo " - Menunggu slot proses tersedia ($(jobs -r | wc -l)/$MAX_JOBS berjalan)..."
done
done

echo ""
echo "Menunggu semua proses selesai..."
wait

echo ""
echo "=============================================="
echo " PROSES SELESAI"
echo "=============================================="
echo "Waktu selesai: $(date)"
echo ""

echo "Membuat summary..."
echo "SAMPLE,INPUT_READS,OUTPUT_READS,Q20_RATE,Q30_RATE,GC_RATE" > "$LOG_DIR/fastp_summary.csv"

for json_file in "$OUTPUT_DIR"/*_fastp.json; do
if [ -f "$json_file" ]; then
sample=$(basename "$json_file" | sed 's/_fastp.json//')
input_reads=$(jq '.summary.before_filtering.total_reads' "$json_file")
output_reads=$(jq '.summary.after_filtering.total_reads' "$json_file")
q20_rate=$(jq '.summary.after_filtering.q20_rate' "$json_file")
q30_rate=$(jq '.summary.after_filtering.q30_rate' "$json_file")
gc_rate=$(jq '.summary.after_filtering.gc_content' "$json_file")
echo "$sample,$input_reads,$output_reads,$q20_rate,$q30_rate,$gc_rate" >> "$LOG_DIR/fastp_summary.csv"
fi
done

echo "Summary disimpan di: $LOG_DIR/fastp_summary.csv"
echo ""
cat "$LOG_DIR/fastp_summary.csv" | column -t -s ','
echo ""
echo "Log individual tersedia di: $LOG_DIR/*_fastp.log"
echo "File output tersedia di: $OUTPUT_DIR/"
echo "=============================================="
