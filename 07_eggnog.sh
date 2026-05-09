#!/bin/bash
# Script: 07_eggnog.sh
# EggNOG-mapper parallel pipeline

# ===== KONFIGURASI =====
INPUT_DIR="/data/work/proteins"
OUT_DIR="/data/work/eggnog_output"
DB_DIR="/data/work/eggnog"
TEMP_DIR="/tmp/eggnog_temp_$$"
THREADS=8
PARALLEL_JOBS=4

mkdir -p "$Out_DIR" "$TEMP_DIR"

export EGGNOG_DATA_DIR="$DB_DIR"

echo "=========================================================="
echo "🥚 EGGNOG-MAPPER PARALLEL PIPELINE"
echo "=========================================================="
echo "Input: $INPUT_DIR"
echo "Output: $Out_DIR"
echo "Database: $DB_DIR"
echo "Temp: $TEMP_DIR"
echo "Parallel: $PARALLEL_JOBS jobs, $THREADS threads/job"
echo "Start: $(date)"
echo "=========================================================="

# ===== DAFTAR SAMPEL =====
# Edit array ini sesuai sampel kamu
SPECIFIC_SAMPLES=(
"QML5200-240522-08A-7"
"QML5200-240522-13A-3"
"QML6500-240502-02A-3"
"QML6500-240502-09A-3"
"QML6500-240503-03A-3"
"QML6500-240503-04A-3"
"QML6500-240503-05A-3"
"QML6500-240503-06A-3"
"QML6500-240503-10A-3"
"QML6500-240503-13A-3"
"QML7028-240503-08A-1"
)

echo "🎯 PROCESSING ${#SPECIFIC_SAMPLES[@]} SAMPLES"
printf '%s\n' "${SPECIFIC_SAMPLES[@]}"
echo ""

FAA_FILES=()
for SAMPLE in "${SPECIFIC_SAMPLES[@]}"; do
FAA_FILE="$INPUT_DIR/${SAMPLE}.protein.faa"
if [[ -f "$FAA_FILE" ]]; then
FAA_FILES+=("$FAA_FILE")
echo "✅ Found: $FAA_FILE"
else
echo "❌ Missing: $FAA_FILE"
fi
done

if [[ ${#FAA_FILES[@]} -eq 0 ]]; then
echo "❌ ERROR: No .faa files found"
exit 1
fi

echo ""
echo "📊 Found ${#FAA_FILES[@]} .faa files to process"

# ===== FUNGSI PROSES =====
process_faa() {
local FAA_FILE="$1"
local BASE_NAME=$(basename "$FAA_FILE" .faa)
local JOB_TEMP_DIR="$TEMP_DIR/${BASE_NAME}_$$"

mkdir -p "$JOB_TEMP_DIR"
echo "[$(date '+%H:%M:%S')] 🚀 START: $BASE_NAME"

# Skip jika sudah ada hasil valid
if [[ -f "$Out_DIR/${BASE_NAME}_eggnog.emapper.annotations" ]]; then
local ANNOTATED_COUNT=$(tail -n +6 "$Out_DIR/${BASE_NAME}_eggnog.emapper.annotations" | grep -v "^#" | wc -l)
if [[ $ANNOTATED_COUNT -gt 0 ]]; then
echo "[$(date '+%H:%M:%S')] ⏭️ SKIP: $ANNOTATED_COUNT annotations exist - $BASE_NAME"
return 0
else
echo "[$(date '+%H:%M:%S')] 🔄 RE-RUN: Empty annotations - $BASE_NAME"
rm -f "$Out_DIR/${BASE_NAME}_eggnog.emapper."*
fi
fi

echo "[$(date '+%H:%M:%S')] ➡ PROCESSING: $BASE_NAME"

emapper.py \
-i "$FAA_FILE" \
-o "${BASE_NAME}_eggnog" \
--cpu "$THREADS" \
--data_dir "$DB_DIR" \
--temp_dir "$JOB_TEMP_DIR" \
--output_dir "$Out_DIR" \
--override 2>&1 | while IFS= read -r line; do
echo "[$(date '+%H:%M:%S')] $BASE_NAME: $line"
done

local EXIT_CODE=$?

if [[ $EXIT_CODE -eq 0 ]]; then
echo "[$(date '+%H:%M:%S')] ✅ COMPLETED: $BASE_NAME"
local FINAL_COUNT=$(tail -n +6 "$Out_DIR/${BASE_NAME}_eggnog.emapper.annotations" 2>/dev/null | grep -v "^#" | wc -l)
echo "[$(date '+%H:%M:%S')] 📈 FINAL: $FINAL_COUNT annotated proteins - $BASE_NAME"
else
echo "[$(date '+%H:%M:%S')] ❌ FAILED: $BASE_NAME (exit: $EXIT_CODE)"
fi

rm -rf "$JOB_TEMP_DIR"
}

export -f process_faa
export INPUT_DIR Out_DIR DB_DIR TEMP_DIR THREADS

# ===== PROGRESS MONITOR =====
monitor_progress() {
while true; do
COMPLETED=0
TOTAL=${#FAA_FILES[@]}
for FAA in "${FAA_FILES[@]}"; do
BASE_NAME=$(basename "$FAA" .faa)
ANNOTATIONS_FILE="$Out_DIR/${BASE_NAME}_eggnog.emapper.annotations"
if [[ -f "$ANNOTATIONS_FILE" ]]; then
COUNT=$(tail -n +6 "$ANNOTATIONS_FILE" | grep -v "^#" | wc -l 2>/dev/null || echo 0)
if [[ $COUNT -gt 0 ]]; then ((COMPLETED++)); fi
fi
done
echo "[$(date '+%H:%M:%S')] 📈 PROGRESS: $COMPLETED/$TOTAL completed"
sleep 30
done
}

monitor_progress &
MONITOR_PID=$!

# ===== EKSEKUSI =====
echo "⚡ Starting parallel processing..."
printf "%s\n" "${FAA_FILES[@]}" | parallel -j "$PARALLEL_JOBS" --eta --progress process_faa {}

kill $MONITOR_PID 2>/dev/null

# ===== SUMMARY =====
echo "=========================================================="
echo "🎉 PIPELINE COMPLETED: $(date)"
echo "=========================================================="

COMPLETED_FILES=0
TOTAL_ANNOTATIONS=0

for FAA in "${FAA_FILES[@]}"; do
BASE_NAME=$(basename "$FAA" .faa)
ANNOTATIONS_FILE="$Out_DIR/${BASE_NAME}_eggnog.emapper.annotations"
if [[ -f "$ANNOTATIONS_FILE" ]]; then
COUNT=$(tail -n +6 "$ANNOTATIONS_FILE" | grep -v "^#" | wc -l 2>/dev/null || echo 0)
if [[ $COUNT -gt 0 ]]; then
((COMPLETED_FILES++))
TOTAL_ANNOTATIONS=$((TOTAL_ANNOTATIONS + COUNT))
fi
fi
done

echo "📊 FINAL RESULTS:"
echo " Total files: ${#FAA_FILES[@]}"
echo " Successfully annotated: $COMPLETED_FILES"
echo " Total annotations: $TOTAL_ANNOTATIONS"
[[ ${#FAA_FILES[@]} -gt 0 ]] && echo " Success rate: $((COMPLETED_FILES * 100 / ${#FAA_FILES[@]}))%"

echo ""
echo "📁 OUTPUT FILES:"
for ANN in "$Out_DIR"/*.emapper.annotations; do
if [[ -f "$ANN" ]]; then
COUNT=$(tail -n +6 "$ANN" | grep -v "^#" | wc -l 2>/dev/null || echo 0)
echo " $(basename $ANN): $COUNT annotations"
fi
done

rm -rf "$TEMP_DIR"
echo "=========================================================="
