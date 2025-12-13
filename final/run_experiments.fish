#!/usr/bin/env fish

# NetLogo Headless Runner for Rumor Propagation Experiments
# Run all experiments without GUI for faster execution

# ============================================================================
# CONFIGURATION - UPDATE THESE PATHS
# ============================================================================

# Find your NetLogo installation with:
#   find ~ /usr /opt -name "netlogo-headless.sh" 2>/dev/null

set NETLOGO_PATH "/usr/local/NetLogo-7.1/netlogo-headless.sh"
# Alternative locations to try:
# set NETLOGO_PATH "$HOME/NetLogo-7.1/netlogo-headless.sh"
# set NETLOGO_PATH "/opt/NetLogo-7.1/netlogo-headless.sh"

set MODEL_PATH (pwd)/model.nlogo
set OUTPUT_DIR (pwd)/results
set NUM_THREADS 4  # Adjust based on your CPU cores

# ============================================================================
# SETUP
# ============================================================================

# Create output directory
mkdir -p $OUTPUT_DIR

# Check if NetLogo exists
if not test -f $NETLOGO_PATH
    echo "❌ Error: NetLogo not found at: $NETLOGO_PATH"
    echo ""
    echo "Please update NETLOGO_PATH in this script."
    echo "Find NetLogo with: find ~ /usr /opt -name 'netlogo-headless.sh' 2>/dev/null"
    exit 1
end

# Check if model exists
if not test -f $MODEL_PATH
    echo "❌ Error: Model not found at: $MODEL_PATH"
    echo "Please run this script from the directory containing model.nlogo"
    exit 1
end

echo "🔬 Running NetLogo Experiments Headless"
echo "========================================"
echo "NetLogo: $NETLOGO_PATH"
echo "Model:   $MODEL_PATH"
echo "Output:  $OUTPUT_DIR"
echo "Threads: $NUM_THREADS"
echo ""

# ============================================================================
# EXPERIMENT 1: False vs True Rumor (MOST IMPORTANT)
# ============================================================================

echo "📊 [1/3] Running: false-vs-true-rumor"
echo "   Description: Core research question"
echo "   Runs: 40 (20 reps × 2 conditions)"
echo "   Est. time: ~3-5 minutes"

$NETLOGO_PATH \
    --model $MODEL_PATH \
    --experiment false-vs-true-rumor \
    --table $OUTPUT_DIR/exp1_false_vs_true.csv \
    --threads $NUM_THREADS

if test $status -eq 0
    echo "   ✅ Complete! Saved: exp1_false_vs_true.csv"
    echo ""
else
    echo "   ❌ Failed! Check experiment name in BehaviorSpace"
    echo ""
end

# ============================================================================
# EXPERIMENT 2: Heterogeneity Effect
# ============================================================================

echo "📊 [2/3] Running: heterogeneity-effect"
echo "   Description: Lu (2019) replication"
echo "   Runs: 210"
echo "   Est. time: ~10-15 minutes"

$NETLOGO_PATH \
    --model $MODEL_PATH \
    --experiment heterogeneity-effect \
    --table $OUTPUT_DIR/exp2_heterogeneity.csv \
    --threads $NUM_THREADS

if test $status -eq 0
    echo "   ✅ Complete! Saved: exp2_heterogeneity.csv"
    echo ""
else
    echo "   ❌ Failed! Check experiment name in BehaviorSpace"
    echo ""
end

# ============================================================================
# EXPERIMENT 3: Network Structure Effect
# ============================================================================

echo "📊 [3/3] Running: network-structure-effect"
echo "   Description: Compare network topologies"
echo "   Runs: 120"
echo "   Est. time: ~5-10 minutes"

$NETLOGO_PATH \
    --model $MODEL_PATH \
    --experiment network-structure-effect \
    --table $OUTPUT_DIR/exp3_networks.csv \
    --threads $NUM_THREADS

if test $status -eq 0
    echo "   ✅ Complete! Saved: exp3_networks.csv"
    echo ""
else
    echo "   ❌ Failed! Check experiment name in BehaviorSpace"
    echo ""
end

# ============================================================================
# SUMMARY
# ============================================================================

echo "========================================"
echo "🎉 Experiment run complete!"
echo ""
echo "Results saved in: $OUTPUT_DIR"
echo ""
echo "Next steps:"
echo "  1. Check results: ls -lh $OUTPUT_DIR"
echo "  2. Analyze data:  python3 analyze_experiments.py"
echo ""
echo "Files created:"
ls -lh $OUTPUT_DIR/*.csv 2>/dev/null

# Optional: Run Python analysis automatically
if test -f analyze_experiments.py
    echo ""
    echo "🔍 Running automated analysis..."
    python3 analyze_experiments.py
end
