"""
Rumor Propagation Experiment Analysis
Analyzes BehaviorSpace output from NetLogo model
Optimized for time-series false vs true rumor experiment
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from scipy import stats
from scipy.optimize import curve_fit
import warnings
warnings.filterwarnings('ignore')

# Set style
sns.set_style("whitegrid")
plt.rcParams['figure.figsize'] = (12, 8)

def load_experiment_data(filepath):
    """
    Load NetLogo BehaviorSpace output CSV
    NetLogo table format has 6 header rows before the actual data
    """
    df = pd.read_csv(filepath, skiprows=6)
    
    # Normalize rumor-is-true? column to string 'true'/'false'
    if 'rumor-is-true?' in df.columns:
        # Handle boolean values (True/False) or string values ('"true"'/'"false"')
        df['rumor-is-true?'] = df['rumor-is-true?'].astype(str).str.strip('"').str.lower()
    
    # Clean up network-type column
    if 'network-type' in df.columns:
        df['network-type'] = df['network-type'].astype(str).str.strip('"')
    
    return df

def analyze_false_vs_true_timeseries(df):
    """
    Comprehensive analysis of false vs true rumor experiment with time-series data
    """
    print("=" * 80)
    print("FALSE VS TRUE RUMOR COMPARISON - TIME SERIES ANALYSIS")
    print("=" * 80)
    
    # Check if this is time-series data
    has_timeseries = 'ticks' in df.columns
    
    if not has_timeseries:
        print("⚠️  No time-series data found (no 'ticks' column)")
        print("    Performing end-state analysis only...")
        df['ticks'] = 0  # Treat as single time point
    
    # Separate by truth value
    true_rumors = df[df['rumor-is-true?'] == 'true']
    false_rumors = df[df['rumor-is-true?'] == 'false']
    
    print(f"\n📊 Dataset Info:")
    print(f"  Total data points: {len(df)}")
    print(f"  True rumor runs: {len(true_rumors['[run number]'].unique()) if '[run number]' in df.columns else 'N/A'}")
    print(f"  False rumor runs: {len(false_rumors['[run number]'].unique()) if '[run number]' in df.columns else 'N/A'}")
    if has_timeseries:
        print(f"  Time range: {df['ticks'].min():.0f} to {df['ticks'].max():.0f} ticks")
    
    # Define metrics with their new column names
    metrics = [
        ('Awareness (%)', 'count turtles with [rumor-known?] / population-size', 100),
        ('Mean Belief', 'mean [belief] of turtles', 1),
        ('Aware Mean Belief', 'ifelse-value (any? turtles with [rumor-known?]) [mean [belief] of turtles with [rumor-known?]] [0]', 1),
        ('Strong Believers (%)', 'count turtles with [belief > 0.5] / population-size', 100),
        ('Very Strong Believers (%)', 'count turtles with [belief > 0.7] / population-size', 100),
        ('Belief Variance', 'variance [belief] of turtles', 1),
        ('Max Belief', 'max [belief] of turtles', 1),
    ]
    
    # 1. TIME SERIES VISUALIZATION
    if has_timeseries:
        print("\n" + "=" * 80)
        print("📈 TIME SERIES DYNAMICS")
        print("=" * 80)
        
        fig, axes = plt.subplots(2, 3, figsize=(18, 10))
        fig.suptitle('Rumor Spread Dynamics: False vs True Rumors', fontsize=16, fontweight='bold')
        axes = axes.flatten()
        
        for idx, (metric_name, col_name, scale) in enumerate(metrics[:6]):
            if col_name not in df.columns:
                continue
                
            ax = axes[idx]
            
            # Plot individual runs with transparency
            for run_num in true_rumors['[run number]'].unique():
                run_data = true_rumors[true_rumors['[run number]'] == run_num].sort_values('ticks')
                ax.plot(run_data['ticks'], run_data[col_name] * scale, 
                       alpha=0.1, color='green', linewidth=0.5)
            
            for run_num in false_rumors['[run number]'].unique():
                run_data = false_rumors[false_rumors['[run number]'] == run_num].sort_values('ticks')
                ax.plot(run_data['ticks'], run_data[col_name] * scale,
                       alpha=0.1, color='red', linewidth=0.5)
            
            # Plot mean trajectories with confidence intervals
            for truth_val, color, label in [('true', 'green', 'True Rumors'), 
                                             ('false', 'red', 'False Rumors')]:
                subset = df[df['rumor-is-true?'] == truth_val]
                grouped = subset.groupby('ticks')[col_name]
                
                mean_traj = grouped.mean() * scale
                std_traj = grouped.std() * scale
                sem_traj = grouped.sem() * scale
                
                ax.plot(mean_traj.index, mean_traj.values,
                       color=color, linewidth=3, label=label)
                
                # 95% confidence interval
                ax.fill_between(mean_traj.index,
                               mean_traj.values - 1.96*sem_traj.values,
                               mean_traj.values + 1.96*sem_traj.values,
                               color=color, alpha=0.2)
            
            ax.set_xlabel('Time (ticks)', fontsize=10)
            ax.set_ylabel(metric_name, fontsize=10)
            ax.set_title(metric_name, fontsize=11, fontweight='bold')
            ax.legend(fontsize=9)
            ax.grid(True, alpha=0.3)
        
        plt.tight_layout()
        plt.savefig('pngs/timeseries_dynamics.png', dpi=300, bbox_inches='tight')
        print("✅ Saved: pngs/timeseries_dynamics.png")
        plt.close()
    
    # 2. END-STATE COMPARISON (Final tick values)
    print("\n" + "=" * 80)
    print("📊 END-STATE COMPARISON (Final Values)")
    print("=" * 80)
    
    # Get final values for each run
    if has_timeseries and '[run number]' in df.columns:
        final_values = df.loc[df.groupby('[run number]')['ticks'].idxmax()]
    else:
        final_values = df
    
    true_final = final_values[final_values['rumor-is-true?'] == 'true']
    false_final = final_values[final_values['rumor-is-true?'] == 'false']
    
    print(f"\nComparison based on {len(true_final)} true and {len(false_final)} false rumor runs\n")
    
    for metric_name, col_name, scale in metrics:
        if col_name not in final_values.columns:
            continue
            
        true_vals = true_final[col_name] * scale
        false_vals = false_final[col_name] * scale
        
        true_mean = true_vals.mean()
        true_std = true_vals.std()
        false_mean = false_vals.mean()
        false_std = false_vals.std()
        
        print(f"{metric_name}:")
        print(f"  True  Rumors: {true_mean:.4f} ± {true_std:.4f}")
        print(f"  False Rumors: {false_mean:.4f} ± {false_std:.4f}")
        print(f"  Difference:   {false_mean - true_mean:+.4f}")
        
        # T-test
        t_stat, p_value = stats.ttest_ind(false_vals, true_vals)
        sig = '***' if p_value < 0.001 else '**' if p_value < 0.01 else '*' if p_value < 0.05 else 'ns'
        print(f"  T-test: t={t_stat:.3f}, p={p_value:.4f} {sig}")
        
        # Effect size (Cohen's d)
        pooled_std = np.sqrt(((len(true_vals)-1)*true_std**2 + (len(false_vals)-1)*false_std**2) / 
                            (len(true_vals)+len(false_vals)-2))
        if pooled_std > 0:
            cohens_d = (false_mean - true_mean) / pooled_std
            effect_label = 'small' if abs(cohens_d) < 0.5 else 'medium' if abs(cohens_d) < 0.8 else 'large'
            print(f"  Cohen's d: {cohens_d:.3f} ({effect_label} effect)")
        print()
    
    # 3. END-STATE VISUALIZATION
    # Exclude Awareness and Very Strong Believers from comparison plots
    comparison_metrics = [
        ('Mean Belief', 'mean [belief] of turtles', 1),
        ('Aware Mean Belief', 'ifelse-value (any? turtles with [rumor-known?]) [mean [belief] of turtles with [rumor-known?]] [0]', 1),
        ('Strong Believers (%)', 'count turtles with [belief > 0.5] / population-size', 100),
        ('Belief Variance', 'variance [belief] of turtles', 1),
    ]
    
    fig, axes = plt.subplots(2, 2, figsize=(12, 9))
    fig.suptitle('False vs True Rumor: Final State Comparison', fontsize=16, fontweight='bold')
    axes = axes.flatten()
    
    for idx, (metric_name, col_name, scale) in enumerate(comparison_metrics):
        if col_name not in final_values.columns:
            continue
            
        ax = axes[idx]
        
        # Prepare data for plotting
        plot_data = final_values[['rumor-is-true?', col_name]].copy()
        plot_data[col_name] = plot_data[col_name] * scale
        
        # Violin plot with box plot overlay
        parts = ax.violinplot([true_final[col_name] * scale, false_final[col_name] * scale],
                              positions=[0, 1], widths=0.7, showmeans=True, showmedians=True)
        
        # Color the violins
        for pc, color in zip(parts['bodies'], ['green', 'red']):
            pc.set_facecolor(color)
            pc.set_alpha(0.3)
        
        # Add individual points
        ax.scatter([0] * len(true_final), true_final[col_name] * scale, 
                  alpha=0.4, s=30, color='green', edgecolors='darkgreen', linewidths=0.5)
        ax.scatter([1] * len(false_final), false_final[col_name] * scale,
                  alpha=0.4, s=30, color='red', edgecolors='darkred', linewidths=0.5)
        
        ax.set_xticks([0, 1])
        ax.set_xticklabels(['True', 'False'])
        ax.set_xlabel('Rumor Truth Value', fontsize=10)
        ax.set_ylabel(metric_name, fontsize=10)
        ax.set_title(metric_name, fontsize=11, fontweight='bold')
        ax.grid(True, alpha=0.3, axis='y')
        
        # Add significance annotation
        t_stat, p_value = stats.ttest_ind(false_final[col_name] * scale, true_final[col_name] * scale)
        if p_value < 0.05:
            y_max = max(true_final[col_name].max(), false_final[col_name].max()) * scale
            ax.plot([0, 1], [y_max*1.05, y_max*1.05], 'k-', linewidth=1.5)
            stars = '***' if p_value < 0.001 else '**' if p_value < 0.01 else '*'
            ax.text(0.5, y_max*1.08, stars, ha='center', fontsize=14, fontweight='bold')
    
    plt.tight_layout()
    plt.savefig('pngs/false_vs_true_comparison.png', dpi=300, bbox_inches='tight')
    print("\n✅ Saved: pngs/false_vs_true_comparison.png")
    plt.close()
    
    # 4. GROWTH RATE ANALYSIS
    if has_timeseries and '[run number]' in df.columns:
        print("\n" + "=" * 80)
        print("📈 GROWTH RATE ANALYSIS")
        print("=" * 80)
        
        awareness_col = 'count turtles with [rumor-known?] / population-size'
        if awareness_col in df.columns:
            # Calculate growth rates for each run
            growth_rates = []
            
            for truth_val in ['true', 'false']:
                subset = df[df['rumor-is-true?'] == truth_val]
                
                for run_num in subset['[run number]'].unique():
                    run_data = subset[subset['[run number]'] == run_num].sort_values('ticks')
                    
                    # Find steepest growth period (max derivative)
                    awareness = run_data[awareness_col].values
                    ticks = run_data['ticks'].values
                    
                    if len(awareness) > 10:
                        # Calculate rolling growth rate
                        growth_rate = np.gradient(awareness, ticks)
                        max_growth_rate = np.max(growth_rate)
                        
                        growth_rates.append({
                            'rumor_type': truth_val,
                            'run': run_num,
                            'max_growth_rate': max_growth_rate
                        })
            
            growth_df = pd.DataFrame(growth_rates)
            
            print("\nMaximum Growth Rate (awareness/tick):")
            for truth_val in ['true', 'false']:
                vals = growth_df[growth_df['rumor_type'] == truth_val]['max_growth_rate']
                print(f"  {truth_val.capitalize()} rumors: {vals.mean():.4f} ± {vals.std():.4f}")
            
            # T-test on growth rates
            true_growth = growth_df[growth_df['rumor_type'] == 'true']['max_growth_rate']
            false_growth = growth_df[growth_df['rumor_type'] == 'false']['max_growth_rate']
            t_stat, p_value = stats.ttest_ind(false_growth, true_growth)
            print(f"\n  T-test: t={t_stat:.3f}, p={p_value:.4f}")
    
    return final_values

def generate_summary_report(df):
    """Generate comprehensive summary statistics"""
    print("\n" + "=" * 80)
    print("📋 SUMMARY STATISTICS")
    print("=" * 80)
    
    # Save detailed summary
    summary = df.describe()
    summary.to_csv('results/false_vs_true_summary_stats.csv')
    print("✅ Saved: results/false_vs_true_summary_stats.csv")
    
    # Key findings summary
    print("\n🔍 KEY FINDINGS:")
    
    awareness_col = 'count turtles with [rumor-known?] / population-size'
    if awareness_col in df.columns:
        # Get final values
        if '[run number]' in df.columns and 'ticks' in df.columns:
            final_values = df.loc[df.groupby('[run number]')['ticks'].idxmax()]
        else:
            final_values = df
        
        true_awareness = final_values[final_values['rumor-is-true?'] == 'true'][awareness_col].mean()
        false_awareness = final_values[final_values['rumor-is-true?'] == 'false'][awareness_col].mean()
        
        if false_awareness > true_awareness:
            print(f"  ⚠️  FALSE rumors spread MORE widely ({false_awareness*100:.1f}% vs {true_awareness*100:.1f}%)")
        else:
            print(f"  ✓ TRUE rumors spread more widely ({true_awareness*100:.1f}% vs {false_awareness*100:.1f}%)")

# Main analysis pipeline
if __name__ == "__main__":
    print("🔬 RUMOR PROPAGATION ANALYSIS")
    print("=" * 80)
    print("Analyzing: False vs True Rumor Time-Series Experiment")
    print("=" * 80)
    
    import os
    
    # Create output directory if it doesn't exist
    os.makedirs('pngs', exist_ok=True)
    os.makedirs('results', exist_ok=True)
    
    # Primary experiment file
    experiment_file = 'results/false_vs_true_rumor-table.csv'
    
    # Alternative file names to check
    alternative_files = [
        'false_vs_true_rumor-table.csv',
        'results/exp1_false_vs_true.csv',
        'model false-vs-true-rumor-table.csv',
        'results/model false-vs-true-rumor-table.csv'
    ]
    
    # Find the experiment file
    data_file = None
    if os.path.exists(experiment_file):
        data_file = experiment_file
    else:
        for alt_file in alternative_files:
            if os.path.exists(alt_file):
                data_file = alt_file
                break
    
    if data_file is None:
        print("\n❌ ERROR: Experiment data file not found!")
        print("\nLooked for:")
        print(f"  • {experiment_file}")
        for alt in alternative_files:
            print(f"  • {alt}")
        print("\n💡 Please run the experiment first using:")
        print("   1. Open NetLogo")
        print("   2. Load atp_code_g25.nlogo")
        print("   3. Tools → BehaviorSpace")
        print("   4. Run 'false-vs-true-rumor' experiment")
        print("   5. Save results to results/ directory")
        exit(1)
    
    print(f"\n📂 Loading data from: {data_file}")
    
    try:
        # Load data
        df = load_experiment_data(data_file)
        print(f"✅ Loaded {len(df)} data points successfully")
        
        # Perform analysis
        final_values = analyze_false_vs_true_timeseries(df)
        generate_summary_report(df)
        
        print("\n" + "=" * 80)
        print("✅ ANALYSIS COMPLETE!")
        print("=" * 80)
        print("\n📁 Generated files:")
        print("   • pngs/timeseries_dynamics.png")
        print("   • pngs/false_vs_true_comparison.png")
        print("   • results/false_vs_true_summary_stats.csv")
        print("\n📊 Use these figures in your research paper!")
        
    except Exception as e:
        print(f"\n❌ ERROR during analysis: {e}")
        import traceback
        traceback.print_exc()
