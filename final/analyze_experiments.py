"""
Rumor Propagation Experiment Analysis
Analyzes BehaviorSpace output from NetLogo model
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from scipy import stats
from scipy.optimize import curve_fit

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

def analyze_false_vs_true(df):
    """
    Analyze Experiment 1: False vs True Rumor Comparison
    """
    print("=" * 70)
    print("EXPERIMENT 1: FALSE VS TRUE RUMOR COMPARISON")
    print("=" * 70)
    
    # Separate by truth value
    true_rumors = df[df['rumor-is-true?'] == 'true']
    false_rumors = df[df['rumor-is-true?'] == 'false']
    
    # Calculate statistics
    print("\n📊 DESCRIPTIVE STATISTICS")
    print("-" * 70)
    
    metrics = [
        ('Awareness (%)', 'count turtles with [rumor-known?] / population-size'),
        ('Mean Belief', 'mean [belief] of turtles'),
        ('Strong Believers (%)', 'count turtles with [belief > 0.5]'),
        ('Belief Variance', 'variance [belief] of turtles')
    ]
    
    for metric_name, col_name in metrics:
        if col_name in df.columns:
            true_mean = true_rumors[col_name].mean()
            true_std = true_rumors[col_name].std()
            false_mean = false_rumors[col_name].mean()
            false_std = false_rumors[col_name].std()
            
            print(f"\n{metric_name}:")
            print(f"  True  Rumors: {true_mean:.4f} ± {true_std:.4f}")
            print(f"  False Rumors: {false_mean:.4f} ± {false_std:.4f}")
            print(f"  Difference:   {false_mean - true_mean:+.4f}")
            
            # T-test
            t_stat, p_value = stats.ttest_ind(false_rumors[col_name], true_rumors[col_name])
            print(f"  T-test: t={t_stat:.3f}, p={p_value:.4f} {'***' if p_value < 0.001 else '**' if p_value < 0.01 else '*' if p_value < 0.05 else 'ns'}")
            
            # Effect size (Cohen's d)
            pooled_std = np.sqrt(((len(true_rumors)-1)*true_std**2 + (len(false_rumors)-1)*false_std**2) / (len(true_rumors)+len(false_rumors)-2))
            cohens_d = (false_mean - true_mean) / pooled_std
            print(f"  Cohen's d: {cohens_d:.3f} ({'small' if abs(cohens_d) < 0.5 else 'medium' if abs(cohens_d) < 0.8 else 'large'} effect)")
    
    # Visualization
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    fig.suptitle('False vs True Rumor Comparison', fontsize=16, fontweight='bold')
    
    for idx, (metric_name, col_name) in enumerate(metrics):
        if col_name in df.columns:
            ax = axes[idx // 2, idx % 2]
            
            # Boxplot
            sns.boxplot(data=df, x='rumor-is-true?', y=col_name, ax=ax, palette=['#2ecc71', '#e74c3c'])
            
            # Add individual points
            sns.stripplot(data=df, x='rumor-is-true?', y=col_name, ax=ax, 
                         color='black', alpha=0.3, size=3)
            
            ax.set_xlabel('Rumor Truth Value', fontsize=11)
            ax.set_ylabel(metric_name, fontsize=11)
            ax.set_title(f'{metric_name}', fontsize=12, fontweight='bold')
            
            # Add significance stars
            y_max = df[col_name].max()
            t_stat, p_value = stats.ttest_ind(false_rumors[col_name], true_rumors[col_name])
            if p_value < 0.05:
                ax.plot([0, 1], [y_max*1.05, y_max*1.05], 'k-', linewidth=1.5)
                stars = '***' if p_value < 0.001 else '**' if p_value < 0.01 else '*'
                ax.text(0.5, y_max*1.08, stars, ha='center', fontsize=14)
    
    plt.tight_layout()
    plt.savefig('false_vs_true_comparison.png', dpi=300, bbox_inches='tight')
    print("\n✅ Saved: false_vs_true_comparison.png")
    plt.show()
    
    return true_rumors, false_rumors

def analyze_heterogeneity_effect(df):
    """
    Analyze Experiment 2: Heterogeneity Effect
    """
    print("\n" + "=" * 70)
    print("EXPERIMENT 2: HETEROGENEITY EFFECT (Lu 2019 Replication)")
    print("=" * 70)
    
    # Linear regression
    from sklearn.linear_model import LinearRegression
    
    awareness_col = 'count turtles with [rumor-known?] / population-size'
    
    if awareness_col in df.columns:
        # Separate by truth value
        for truth_val in ['true', 'false']:
            subset = df[df['rumor-is-true?'] == truth_val]
            
            X = subset['heterogeneity-level'].values.reshape(-1, 1)
            y = subset[awareness_col].values
            
            # Regression
            model = LinearRegression()
            model.fit(X, y)
            
            # Calculate R²
            r_squared = model.score(X, y)
            slope = model.coef_[0]
            intercept = model.intercept_
            
            print(f"\n📈 {truth_val.upper()} RUMORS:")
            print(f"  Equation: awareness = {intercept:.4f} + {slope:.4f} × heterogeneity")
            print(f"  R² = {r_squared:.4f}")
            print(f"  Slope {'positive ✓' if slope > 0 else 'negative ✗'} (Lu predicts positive)")
            
            # Significance test
            from scipy.stats import pearsonr
            corr, p_value = pearsonr(subset['heterogeneity-level'], subset[awareness_col])
            print(f"  Correlation: r={corr:.3f}, p={p_value:.4f}")
        
        # Visualization
        fig, axes = plt.subplots(1, 2, figsize=(14, 5))
        fig.suptitle('Heterogeneity Effect on Rumor Spread', fontsize=16, fontweight='bold')
        
        for idx, truth_val in enumerate(['true', 'false']):
            ax = axes[idx]
            subset = df[df['rumor-is-true?'] == truth_val]
            
            # Scatter plot
            sns.scatterplot(data=subset, x='heterogeneity-level', y=awareness_col, 
                           ax=ax, alpha=0.6, s=80)
            
            # Regression line
            X = subset['heterogeneity-level'].values.reshape(-1, 1)
            y = subset[awareness_col].values
            model = LinearRegression()
            model.fit(X, y)
            
            x_line = np.linspace(X.min(), X.max(), 100)
            y_line = model.predict(x_line.reshape(-1, 1))
            ax.plot(x_line, y_line, 'r-', linewidth=2, label=f'R²={model.score(X, y):.3f}')
            
            ax.set_xlabel('Heterogeneity Level', fontsize=11)
            ax.set_ylabel('Awareness Proportion', fontsize=11)
            ax.set_title(f'{truth_val.capitalize()} Rumors', fontsize=12, fontweight='bold')
            ax.legend()
            ax.grid(True, alpha=0.3)
        
        plt.tight_layout()
        plt.savefig('heterogeneity_effect.png', dpi=300, bbox_inches='tight')
        print("\n✅ Saved: heterogeneity_effect.png")
        plt.show()

def analyze_network_structure(df):
    """
    Analyze Experiment 3: Network Structure Effect
    """
    print("\n" + "=" * 70)
    print("EXPERIMENT 3: NETWORK STRUCTURE EFFECT")
    print("=" * 70)
    
    # ANOVA
    from scipy.stats import f_oneway
    
    awareness_col = 'count turtles with [rumor-known?] / population-size'
    
    if awareness_col in df.columns:
        # Separate by truth value
        for truth_val in ['true', 'false']:
            subset = df[df['rumor-is-true?'] == truth_val]
            
            random = subset[subset['network-type'] == 'random'][awareness_col]
            small_world = subset[subset['network-type'] == 'small-world'][awareness_col]
            scale_free = subset[subset['network-type'] == 'scale-free'][awareness_col]
            
            # ANOVA
            f_stat, p_value = f_oneway(random, small_world, scale_free)
            
            print(f"\n📊 {truth_val.upper()} RUMORS:")
            print(f"  Random:      {random.mean():.4f} ± {random.std():.4f}")
            print(f"  Small-world: {small_world.mean():.4f} ± {small_world.std():.4f}")
            print(f"  Scale-free:  {scale_free.mean():.4f} ± {scale_free.std():.4f}")
            print(f"  ANOVA: F={f_stat:.3f}, p={p_value:.4f}")
        
        # Visualization
        fig, axes = plt.subplots(1, 2, figsize=(14, 5))
        fig.suptitle('Network Structure Effect on Rumor Spread', fontsize=16, fontweight='bold')
        
        for idx, truth_val in enumerate(['true', 'false']):
            ax = axes[idx]
            subset = df[df['rumor-is-true?'] == truth_val]
            
            sns.boxplot(data=subset, x='network-type', y=awareness_col, ax=ax,
                       palette='Set2')
            sns.stripplot(data=subset, x='network-type', y=awareness_col, ax=ax,
                         color='black', alpha=0.3, size=4)
            
            ax.set_xlabel('Network Type', fontsize=11)
            ax.set_ylabel('Awareness Proportion', fontsize=11)
            ax.set_title(f'{truth_val.capitalize()} Rumors', fontsize=12, fontweight='bold')
            ax.set_xticklabels(['Random', 'Small-World', 'Scale-Free'])
        
        plt.tight_layout()
        plt.savefig('network_structure_effect.png', dpi=300, bbox_inches='tight')
        print("\n✅ Saved: network_structure_effect.png")
        plt.show()

def analyze_time_series(df):
    """
    Analyze Experiment 7: Time Series Dynamics
    """
    print("\n" + "=" * 70)
    print("EXPERIMENT 7: TEMPORAL DYNAMICS")
    print("=" * 70)
    
    awareness_col = 'count turtles with [rumor-known?] / population-size'
    
    if 'ticks' in df.columns and awareness_col in df.columns:
        print(f"✓ Data contains {len(df['[run number]'].unique())} runs")
        print(f"✓ Time range: {df['ticks'].min()} to {df['ticks'].max()} ticks")
        
        # Group by run and calculate mean trajectories
        fig, axes = plt.subplots(1, 2, figsize=(14, 5))
        fig.suptitle('Rumor Growth Dynamics Over Time', fontsize=16, fontweight='bold')
        
        for idx, truth_val in enumerate(['true', 'false']):
            ax = axes[idx]
            subset = df[df['rumor-is-true?'] == truth_val]
            
            if len(subset) == 0:
                print(f"⚠️  No data for {truth_val} rumors")
                continue
            
            print(f"✓ Plotting {len(subset['[run number]'].unique())} runs for {truth_val} rumors")
            
            # Plot individual runs (light lines)
            for run_num in subset['[run number]'].unique():
                run_data = subset[subset['[run number]'] == run_num].sort_values('ticks')
                ax.plot(run_data['ticks'], run_data[awareness_col], 
                       alpha=0.2, color='gray', linewidth=0.5)
            
            # Plot mean trajectory (bold line)
            mean_trajectory = subset.groupby('ticks')[awareness_col].mean()
            ax.plot(mean_trajectory.index, mean_trajectory.values,
                   color='red' if truth_val == 'false' else 'green',
                   linewidth=3, label='Mean')
            
            ax.set_xlabel('Time (ticks)', fontsize=11)
            ax.set_ylabel('Awareness Proportion', fontsize=11)
            ax.set_title(f'{truth_val.capitalize()} Rumors', fontsize=12, fontweight='bold')
            ax.legend()
            ax.grid(True, alpha=0.3)
        
        plt.tight_layout()
        plt.savefig('time_series_dynamics.png', dpi=300, bbox_inches='tight')
        print("\n✅ Saved: time_series_dynamics.png")
        plt.show()

def generate_summary_report(df, experiment_name):
    """Generate comprehensive summary report"""
    print("\n" + "=" * 70)
    print(f"SUMMARY REPORT: {experiment_name}")
    print("=" * 70)
    
    print(f"\n📋 Dataset Information:")
    print(f"  Total runs: {len(df)}")
    print(f"  Parameters varied: {[col for col in df.columns if df[col].nunique() > 1 and col not in ['[run number]', 'ticks']]}")
    print(f"  Metrics collected: {len([col for col in df.columns if '[' in col or 'mean' in col or 'count' in col])}")
    
    # Save summary statistics
    summary = df.describe()
    summary.to_csv(f'{experiment_name}_summary_stats.csv')
    print(f"\n✅ Saved: {experiment_name}_summary_stats.csv")

# Main analysis pipeline
if __name__ == "__main__":
    print("🔬 RUMOR PROPAGATION ANALYSIS - ALL EXPERIMENTS")
    print("=" * 70)
    
    # Define all 8 experiments
    experiments = [
        {
            'name': 'Experiment 1: False vs True Rumor',
            'file': 'results/exp1_false_vs_true.csv',
            'analyses': ['false_vs_true']
        },
        {
            'name': 'Experiment 2: Heterogeneity Effect',
            'file': 'results/exp2_heterogeneity.csv',
            'analyses': ['heterogeneity']
        },
        {
            'name': 'Experiment 3: Network Structure',
            'file': 'results/exp3_networks.csv',
            'analyses': ['network']
        },
        {
            'name': 'Experiment 4: Verification Timing',
            'file': 'results/exp4_verification.csv',
            'analyses': ['summary']
        },
        {
            'name': 'Experiment 5: Learning Rate',
            'file': 'results/exp5_learning.csv',
            'analyses': ['summary']
        },
        {
            'name': 'Experiment 6: Initial Trust',
            'file': 'results/exp6_trust.csv',
            'analyses': ['summary']
        },
        {
            'name': 'Experiment 7: Time Series',
            'file': 'results/exp7_timeseries.csv',
            'analyses': ['timeseries']
        },
        {
            'name': 'Experiment 8: Full Factorial',
            'file': 'results/exp8_factorial.csv',
            'analyses': ['summary']
        }
    ]
    
    # Track which experiments were successfully analyzed
    successful = []
    failed = []
    
    # Process each experiment
    for exp in experiments:
        print(f"\n{'='*70}")
        print(f"📊 {exp['name']}")
        print(f"📂 File: {exp['file']}")
        print('='*70)
        
        try:
            # Check if file exists
            import os
            if not os.path.exists(exp['file']):
                print(f"⏭️  Skipping - file not found")
                failed.append(exp['name'])
                continue
            
            # Load data
            df = load_experiment_data(exp['file'])
            print(f"✅ Loaded {len(df)} runs successfully")
            
            # Run appropriate analyses
            for analysis_type in exp['analyses']:
                if analysis_type == 'false_vs_true' and 'rumor-is-true?' in df.columns:
                    if df['rumor-is-true?'].nunique() == 2:
                        analyze_false_vs_true(df)
                
                elif analysis_type == 'heterogeneity' and 'heterogeneity-level' in df.columns:
                    if df['heterogeneity-level'].nunique() > 1:
                        analyze_heterogeneity_effect(df)
                
                elif analysis_type == 'network' and 'network-type' in df.columns:
                    if df['network-type'].nunique() > 1:
                        analyze_network_structure(df)
                
                elif analysis_type == 'timeseries' and 'ticks' in df.columns:
                    analyze_time_series(df)
                
                elif analysis_type == 'summary':
                    generate_summary_report(df, exp['file'].replace('.csv', ''))
            
            successful.append(exp['name'])
            
        except FileNotFoundError:
            print(f"⏭️  Skipping - file not found")
            failed.append(exp['name'])
        except Exception as e:
            print(f"❌ Error: {e}")
            import traceback
            traceback.print_exc()
            failed.append(exp['name'])
    
    # Final summary
    print("\n" + "=" * 70)
    print("📋 ANALYSIS SUMMARY")
    print("=" * 70)
    
    if successful:
        print(f"\n✅ Successfully analyzed ({len(successful)}):")
        for exp_name in successful:
            print(f"   • {exp_name}")
    
    if failed:
        print(f"\n⏭️  Skipped/Failed ({len(failed)}):")
        for exp_name in failed:
            print(f"   • {exp_name}")
        print(f"\n💡 Tip: Run the experiments first using:")
        print(f"   ./run_experiments.fish")
        print(f"   or manually through BehaviorSpace")
    
    if successful:
        print("\n" + "=" * 70)
        print("✅ ANALYSIS COMPLETE!")
        print("=" * 70)
        print("\n📁 Generated files:")
        print("   • false_vs_true_comparison.png")
        print("   • heterogeneity_effect.png")
        print("   • network_structure_effect.png")
        print("   • time_series_dynamics.png")
        print("   • *_summary_stats.csv")
        print("\n📊 Use these figures in your research paper!")
    else:
        print("\n❌ No experiments were analyzed")
        print("Run experiments first, then re-run this script")
