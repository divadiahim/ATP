#!/bin/bash

# NetLogo Headless Runner for Rumor Propagation Experiments
# Bash version (for compatibility with different systems)

# ============================================================================
# CONFIGURATION - UPDATE THESE PATHS
# ============================================================================

NETLOGO_PATH="/usr/local/NetLogo-7.1/netlogo-headless.sh"
# Alternative locations to try:
# NETLOGO_PATH="$HOME/NetLogo-7.1/netlogo-headless.sh"
# NETLOGO_PATH="/opt/NetLogo-7.1/netlogo-headless.sh"

MODEL_PATH="$(pwd)/model.nlogo"
OUTPUT_DIR="$(pwd)/results"
NUM_THREADS=4

# ============================================================================
# SETUP
# ============================================================================

mkdir -p "$OUTPUT_DIR"

if [ ! -f "$NETLOGO_PATH" ]; then
    echo "❌ Error: NetLogo not found at: $NETLOGO_PATH"
    echo ""
    echo "Please update NETLOGO_PATH in this script."
    echo "Find NetLogo with: find ~ /usr /opt -name 'netlogo-headless.sh' 2>/dev/null"
    exit 1
fi

if [ ! -f "$MODEL_PATH" ]; then
    echo "❌ Error: Model not found at: $MODEL_PATH"
    echo "Please run this script from the directory containing model.nlogo"
    exit 1
fi

echo "🔬 Running NetLogo Experiments Headless"
echo "========================================"
echo "NetLogo: $NETLOGO_PATH"
echo "Model:   $MODEL_PATH"
echo "Output:  $OUTPUT_DIR"
echo "Threads: $NUM_THREADS"
echo ""

# ============================================================================
# EXPERIMENT 1: False vs True Rumor
# ============================================================================

echo "📊 [1/3] Running: false-vs-true-rumor"
echo "   Runs: 40, Est. time: ~3-5 minutes"

"$NETLOGO_PATH" \
    --model "$MODEL_PATH" \
    --experiment false-vs-true-rumor \
    --table "$OUTPUT_DIR/exp1_false_vs_true.csv" \
    --threads "$NUM_THREADS"

if [ $? -eq 0 ]; then
    echo "   ✅ Complete! Saved: exp1_false_vs_true.csv"
else
    echo "   ❌ Failed!"
fi
echo ""

# ============================================================================
# EXPERIMENT 2: Heterogeneity Effect
# ============================================================================

echo "📊 [2/3] Running: heterogeneity-effect"
echo "   Runs: 210, Est. time: ~10-15 minutes"

"$NETLOGO_PATH" \
    --model "$MODEL_PATH" \
    --experiment heterogeneity-effect \
    --table "$OUTPUT_DIR/exp2_heterogeneity.csv" \
    --threads "$NUM_THREADS"

if [ $? -eq 0 ]; then
    echo "   ✅ Complete! Saved: exp2_heterogeneity.csv"
else
    echo "   ❌ Failed!"
fi
echo ""

# ============================================================================
# EXPERIMENT 3: Network Structure
# ============================================================================

echo "📊 [3/3] Running: network-structure-effect"
echo "   Runs: 120, Est. time: ~5-10 minutes"

"$NETLOGO_PATH" \
    --model "$MODEL_PATH" \
    --experiment network-structure-effect \
    --table "$OUTPUT_DIR/exp3_networks.csv" \
    --threads "$NUM_THREADS"

if [ $? -eq 0 ]; then
    echo "   ✅ Complete! Saved: exp3_networks.csv"
else
    echo "   ❌ Failed!"
fi
echo ""

# ============================================================================
# SUMMARY
# ============================================================================

echo "========================================"
echo "🎉 Experiment run complete!"
echo ""
echo "Results saved in: $OUTPUT_DIR"
ls -lh "$OUTPUT_DIR"/*.csv 2>/dev/null
echo ""
echo "Next: python3 analyze_experiments.py"
