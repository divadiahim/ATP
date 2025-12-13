;; ============================================================================
;; RUMOR SPREAD MODEL WITH ADAPTIVE TRUST DYNAMICS
;; Based on Lu (2019) - Heterogeneity, judgment, and social trust in rumor spreading
;; ============================================================================

extensions [table]  ;; Enable table data structure for efficient sparse storage of trust values

;; Global variables shared across all agents
globals [
  rumor-truth?              ;; Boolean: is the rumor actually true or false?
  rumor-known?              ;; Boolean: general tracking of rumor awareness
  avg-belief-history        ;; List: tracks mean belief level over time
  aware-count-history       ;; List: tracks proportion of aware agents over time
  trust-variance-history    ;; List: tracks variance in trust values over time
  verification-tick         ;; Integer: timestep when verification event occurred
  verified?                 ;; Boolean: has the rumor been verified yet?
  
  ;; Model constants (initialized in setup)
  agent-attribute-mean      ;; Mean for judgment-quality and acceptance-threshold (default: 0.5)
  acceptance-threshold-min  ;; Minimum acceptance threshold (default: 0.1)
  acceptance-threshold-max  ;; Maximum acceptance threshold (default: 0.9)
  initial-belief-min        ;; Minimum initial belief for seeds (default: 0.7)
  initial-belief-range      ;; Range for initial belief randomization (default: 0.3)
  default-trust-value       ;; Default trust when no history exists (default: 0.5)
  rewiring-probability      ;; Probability of rewiring in small-world networks (default: 0.1)
  agreement-reinforcement   ;; Reinforcement value for agreement (default: 0.7)
  verification-adjustment   ;; Belief adjustment factor upon verification (default: 0.5)
  base-agent-size           ;; Base size for agent visualization (default: 1.0)
  viz-scale-upper           ;; Upper bound for color scaling (default: 1.2)
  viz-scale-lower           ;; Lower bound for color scaling (default: -0.2)
  trust-link-base-thickness ;; Base thickness for trust links (default: 0.1)
  trust-link-scale-factor   ;; Scaling factor for trust link thickness (default: 0.3)
]

;; Agent-level properties
turtles-own [
  belief                    ;; Float [0,1]: current belief in the rumor
  trust-table               ;; Table: maps neighbor ID -> trust value [0,1]
  times-heard               ;; Integer: number of times agent heard the rumor
  sources-list              ;; List: IDs of agents from whom rumor was heard
  acceptance-threshold      ;; Float [0.1,0.9]: personal threshold for accepting rumors
  judgment-quality          ;; Float [0,1]: agent's ability to assess information accuracy
  message-history           ;; List of [sender-id, sender-belief] pairs for trust updating
]


;; ============================================================================
;; SETUP PROCEDURE
;; Initializes the model: creates agents, builds network, initializes trust
;; ============================================================================
to setup
  clear-all
  set-default-shape turtles "person"
  
  ;; Initialize model constants
  set agent-attribute-mean 0.5
  set acceptance-threshold-min 0.1
  set acceptance-threshold-max 0.9
  set initial-belief-min 0.7
  set initial-belief-range 0.3
  set default-trust-value 0.5
  set rewiring-probability 0.1
  set agreement-reinforcement 0.7
  set verification-adjustment 0.5
  set base-agent-size 1.0
  set viz-scale-upper 1.2
  set viz-scale-lower -0.2
  set trust-link-base-thickness 0.1
  set trust-link-scale-factor 0.3

  ;; Create population of agents
  create-turtles population-size [
    setxy random-xcor random-ycor  ;; Random spatial positioning
    set color gray                  ;; Gray = unaware of rumor
    set rumor-known? false
    set belief 0
    set times-heard 0
    set sources-list []
    set message-history []

    ;; Agent heterogeneity: judgment quality and acceptance threshold
    ;; Drawn from normal distribution with mean agent-attribute-mean and SD = heterogeneity-level
    set judgment-quality random-normal agent-attribute-mean heterogeneity-level
    set judgment-quality max list 0 (min list 1 judgment-quality)  ;; Clamp to [0,1]

    set acceptance-threshold random-normal agent-attribute-mean heterogeneity-level
    set acceptance-threshold max list acceptance-threshold-min (min list acceptance-threshold-max acceptance-threshold)

    ;; Initialize empty trust table (will be populated after network creation)
    set trust-table table:make
  ]

  ;; ========================================
  ;; NETWORK CONSTRUCTION
  ;; Build one of three network types: random, small-world, or scale-free
  ;; ========================================

  ;; Random network: each agent randomly connects to avg-degree neighbors
  if network-type = "random" [
    ask turtles [
      let num-links min list avg-degree (population-size - 1)
      create-links-with n-of num-links other turtles with [not link-neighbor? myself]
    ]
  ]

  ;; Small-world network: ring lattice with local connections + random rewiring
  ;; Based on Watts-Strogatz model
  if network-type = "small-world" [

    let num-neighbors avg-degree
    ;; Step 1: Create ring lattice with local connections
    ask turtles [
      let near-neighbors other turtles with [
        abs (who - [who] of myself) <= num-neighbors / 2 or
        abs (who - [who] of myself) >= population-size - num-neighbors / 2
      ]
      create-links-with near-neighbors
    ]

    ;; Step 2: Randomly rewire links with rewiring-probability
    ask links [
      if random-float 1 < rewiring-probability [
        let node1 end1
        ask node1 [
          let new-partner one-of other turtles with [not link-neighbor? myself]
          if new-partner != nobody [
            ask myself [die]          ;; Remove old link
            create-link-with new-partner  ;; Create new link
          ]
        ]
      ]
    ]
  ]

  ;; Scale-free network: preferential attachment (Barabási-Albert model)
  ;; New nodes preferentially attach to highly connected nodes
  if network-type = "scale-free" [
    ;; Initialize core network
    ask turtle 0 [create-links-with other turtles with [who < avg-degree]]
    let existing-nodes turtles with [who < avg-degree]
    
    ;; Add remaining nodes with preferential attachment
    ask turtles with [who >= avg-degree] [
      let targets n-of (min list avg-degree count existing-nodes) existing-nodes
      create-links-with targets
      set existing-nodes (turtle-set existing-nodes self)
    ]
  ]

  ;; ========================================
  ;; TRUST INITIALIZATION
  ;; Initialize trust values for all network neighbors
  ;; ========================================
  ask turtles [
    ask link-neighbors [
      let neighbor-id who
      ask myself [
        ;; Initial trust drawn from normal distribution
        ;; T_ij(0) ~ N(initial-trust-mean, initial-trust-sd)
        let init-trust random-normal initial-trust-mean initial-trust-sd
        set init-trust max list 0 (min list 1 init-trust)  ;; Clamp to [0,1]
        table:put trust-table neighbor-id init-trust
      ]
    ]
  ]

  ;; ========================================
  ;; RUMOR INITIALIZATION
  ;; Set ground truth and seed initial rumor spreaders
  ;; ========================================
  set rumor-truth? (rumor-is-true? = "true")  ;; Convert string to boolean
  set verified? false
  set verification-tick -1

  ;; Select initial seed agents who know the rumor
  ask n-of initial-seeds turtles [
    set rumor-known? true
    set times-heard 1
    set belief random-float initial-belief-range + initial-belief-min  ;; Strong initial belief
    set color red
  ]

  ;; Initialize tracking lists
  set avg-belief-history []
  set aware-count-history []
  set trust-variance-history []

  reset-ticks
end

;; ============================================================================
;; MAIN EXECUTION LOOP
;; Runs each timestep: spreads rumor, updates trust, records statistics
;; ============================================================================
to go
  ;; Stop condition: maximum time steps reached (if enabled)
  if auto-stop? and ticks >= max-ticks [ stop ]

  ;; Verification event: if enabled, verify rumor at specified delay
  if verify-rumor? and not verified? and ticks = verification-delay [
    verify-rumor
  ]

  ;; Core dynamics: rumor spreading mechanism
  spread-rumor

  ;; Periodic trust updating: every trust-update-interval ticks
  if ticks > 0 and ticks mod trust-update-interval = 0 [
    update-trust
  ]

  ;; Update visualization and record statistics
  update-visualization
  record-stats
  tick
end
;; ============================================================================
;; RUMOR SPREADING MECHANISM
;; Agents who believe the rumor attempt to share it with their neighbors
;; Transmission depends on belief level, trust, and receiver characteristics
;; ============================================================================
to spread-rumor

  ;; Only agents who know the rumor and have positive belief can spread it
  ask turtles with [rumor-known? and belief > 0] [

    let my-neighbors link-neighbors

    if any? my-neighbors [

      ;; Select one random neighbor to share with (per timestep)
      let target one-of my-neighbors
      let target-id [who] of target

      ;; Get trust in the target (not used in transmission, but available)
      let my-trust table:get-or-default trust-table target-id default-trust-value

      ;; Transmission probability = sender's belief level
      ;; Higher belief → more likely to share
      if random-float 1 < belief [

        ;; Target receives the message
        ask target [
          let sender-id [who] of myself
          let sender-belief [belief] of myself

          ;; Get trust in the sender
          let trust-in-sender table:get-or-default trust-table sender-id default-trust-value

          ;; Update exposure tracking
          set times-heard times-heard + 1
          if not member? sender-id sources-list [
            set sources-list lput sender-id sources-list
          ]

          ;; Calculate influence: trust × sender's belief
          let influence trust-in-sender * sender-belief

          ;; Combined threshold accounts for judgment quality
          ;; Better judgment → higher effective threshold (more skeptical)
          let combined-threshold acceptance-threshold * (1 - judgment-quality)

          ;; Accept rumor if: influence exceeds threshold OR heard enough times
          if influence > combined-threshold or times-heard > hearing-threshold [
            set rumor-known? true

            ;; Belief updating: weighted average toward sender's belief
            ;; B_i(t+1) = B_i(t) + T_ij * (B_j(t) - B_i(t))
            let belief-change trust-in-sender * (sender-belief - belief)
            set belief belief + belief-change
            set belief max list 0 (min list 1 belief)  ;; Clamp to [0,1]

            ;; Record message for future trust updating
            set message-history lput (list sender-id sender-belief) message-history
          ]
        ]
      ]
    ]
  ]
end

;; ============================================================================
;; TRUST UPDATING MECHANISM
;; Agents update trust in their neighbors based on information accuracy
;; Implements adaptive learning: T_ij(t+1) = T_ij(t) + α(R_ij - T_ij(t))
;; ============================================================================
to update-trust

  ask turtles [

    ;; Process all messages received since last trust update
    foreach message-history [ msg ->
      let sender-id item 0 msg
      let sender-belief item 1 msg

      ;; Calculate reinforcement signal R_ij based on accuracy
      let reinforcement 0
      ifelse verified? [
        ;; If rumor has been verified, we know the ground truth
        
        ifelse rumor-truth? [
          ;; Rumor is true: reward high belief
          set reinforcement sender-belief
        ] [
          ;; Rumor is false: reward low belief (skepticism)
          set reinforcement (1 - sender-belief)
        ]
      ]  [
        ;; If not yet verified, estimate based on own judgment
        
        ;; Estimated truth = weighted combination of own belief and neutral (default-trust-value)
        ;; Higher judgment quality → more weight on own assessment
        let estimated-truth belief * judgment-quality + (1 - judgment-quality) * default-trust-value
        
        ;; Reward agreement: if both believe or both disbelieve
        if sender-belief > default-trust-value and estimated-truth > default-trust-value [
          set reinforcement agreement-reinforcement
        ]
        if sender-belief < default-trust-value and estimated-truth < default-trust-value [
          set reinforcement agreement-reinforcement
        ]
      ]

      ;; Apply adaptive learning rule
      ;; T_ij(t+1) = T_ij(t) + α(R_ij - T_ij(t))
      let current-trust table:get-or-default trust-table sender-id default-trust-value
      let new-trust current-trust + learning-rate * (reinforcement - current-trust)
      set new-trust max list 0 (min list 1 new-trust)  ;; Clamp to [0,1]
      table:put trust-table sender-id new-trust
    ]

    ;; Clear message history after processing
    set message-history []
  ]
end

;; ============================================================================
;; VERIFICATION EVENT
;; Reveals the ground truth of the rumor to all aware agents
;; Agents adjust beliefs accordingly
;; ============================================================================
to verify-rumor

  set verified? true
  set verification-tick ticks

  ;; Update beliefs of all agents who know the rumor
  ask turtles with [rumor-known?] [
    ifelse rumor-truth? [
      ;; Rumor is TRUE: increase belief toward 1.0
      set belief belief + (1 - belief) * verification-adjustment
    ] [
      ;; Rumor is FALSE: decrease belief toward 0.0
      set belief belief * verification-adjustment
    ]
  ]
end
;; ============================================================================
;; VISUALIZATION UPDATE
;; Updates agent and link appearance based on current state
;; Color intensity and size reflect belief strength
;; ============================================================================
to update-visualization

  ;; Update agent appearance
  ask turtles [
    ifelse rumor-known? [
      ;; Red intensity indicates belief strength
      set color scale-color red belief viz-scale-upper viz-scale-lower
      set size base-agent-size + belief  ;; Size indicates belief strength
    ] [
      ;; Gray indicates unaware
      set color gray
      set size base-agent-size
    ]
  ]

  ;; Update link appearance (if visualization enabled)
  if show-trust-links? [
    ask links [
      let node1 end1
      let node2 end2
      let id1 [who] of node1
      let id2 [who] of node2
      
      ;; Get bidirectional trust values
      let t1 [table:get-or-default trust-table id2 default-trust-value] of node1
      let t2 [table:get-or-default trust-table id1 default-trust-value] of node2
      let avg-trust (t1 + t2) / 2
      
      ;; Blue intensity indicates trust level
      set color scale-color blue avg-trust viz-scale-upper viz-scale-lower
      set thickness trust-link-base-thickness + avg-trust * trust-link-scale-factor  ;; Thickness reflects trust strength
    ]
  ]
end

;; ============================================================================
;; STATISTICS RECORDING
;; Records time-series data for analysis and plotting
;; ============================================================================
to record-stats

  ;; Record mean belief across all agents
  let mean-belief mean [belief] of turtles
  set avg-belief-history lput mean-belief avg-belief-history

  ;; Record proportion of agents aware of rumor
  let prop-aware count turtles with [rumor-known?] / population-size
  set aware-count-history lput prop-aware aware-count-history

  ;; Record variance in trust values across all trust relationships
  let all-trust-values []
  ask turtles [
    foreach table:values trust-table [ t ->
      set all-trust-values lput t all-trust-values
    ]
  ]
  if length all-trust-values > 0 [
    set trust-variance-history lput variance all-trust-values trust-variance-history
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
250
10
687
448
-1
-1
13.0
1
10
1
1
1
0
0
0
1
-16
16
-16
16
1
1
1
ticks
30.0

BUTTON
15
25
88
58
Setup
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
95
25
158
58
Go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

BUTTON
165
25
238
58
Step
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

SLIDER
15
70
237
103
population-size
population-size
10
500
200.0
10
1
NIL
HORIZONTAL

SLIDER
15
110
237
143
avg-degree
avg-degree
1
20
6.0
1
1
NIL
HORIZONTAL

SLIDER
15
150
237
183
initial-seeds
initial-seeds
1
50
5.0
1
1
NIL
HORIZONTAL

CHOOSER
15
190
237
235
network-type
network-type
"random" "small-world" "scale-free"
1

CHOOSER
15
242
237
287
rumor-is-true?
rumor-is-true?
"true" "false"
1

SLIDER
15
295
237
328
heterogeneity-level
heterogeneity-level
0
0.5
0.2
0.05
1
NIL
HORIZONTAL

SLIDER
15
335
237
368
learning-rate
learning-rate
0
0.5
0.1
0.05
1
NIL
HORIZONTAL

SLIDER
15
375
237
408
initial-trust-mean
initial-trust-mean
0
1
0.5
0.05
1
NIL
HORIZONTAL

SLIDER
15
415
237
448
initial-trust-sd
initial-trust-sd
0
0.3
0.15
0.05
1
NIL
HORIZONTAL

SLIDER
15
455
237
488
hearing-threshold
hearing-threshold
1
10
3.0
1
1
NIL
HORIZONTAL

SLIDER
15
495
237
528
trust-update-interval
trust-update-interval
5
50
10.0
5
1
ticks
HORIZONTAL

SLIDER
15
535
237
568
max-ticks
max-ticks
100
2000
500.0
100
1
NIL
HORIZONTAL

SWITCH
15
575
237
608
auto-stop?
auto-stop?
0
1
-1000

SWITCH
15
615
237
648
verify-rumor?
verify-rumor?
0
1
-1000

SLIDER
15
655
237
688
verification-delay
verification-delay
50
500
200.0
50
1
ticks
HORIZONTAL

SWITCH
15
695
237
728
show-trust-links?
show-trust-links?
1
1
-1000

PLOT
700
10
1050
200
Rumor Spread
Time
Proportion
0.0
100.0
0.0
1.0
true
true
"" ""
PENS
"aware" 1.0 0 -2674135 true "" "plot count turtles with [rumor-known?] / population-size"
"believers" 1.0 0 -5825686 true "" "plot count turtles with [belief > 0.5] / population-size"

PLOT
700
210
1050
400
Mean Belief Over Time
Time
Mean Belief
0.0
100.0
0.0
1.0
true
false
"" ""
PENS
"belief" 1.0 0 -16777216 true "" "if length avg-belief-history > 0 [plot last avg-belief-history]"

PLOT
1060
10
1410
200
Trust Variance
Time
Variance
0.0
100.0
0.0
0.1
true
false
"" ""
PENS
"variance" 1.0 0 -13345367 true "" "if length trust-variance-history > 0 [plot last trust-variance-history]"

PLOT
1060
210
1410
400
Belief Distribution
Belief Level
Count
0.0
1.0
0.0
10.0
true
false
"" ""
PENS
"default" 0.05 1 -16777216 true "" "histogram [belief] of turtles"

MONITOR
700
410
797
455
Aware Count
count turtles with [rumor-known?]
0
1
11

MONITOR
805
410
902
455
% Aware
precision (count turtles with [rumor-known?] / population-size * 100) 1
0
1
11

MONITOR
910
410
1007
455
Mean Belief
precision (mean [belief] of turtles) 3
0
1
11

MONITOR
1015
410
1112
455
Verified?
verified?
0
1
11

MONITOR
1120
410
1217
455
Ground Truth
rumor-truth?
0
1
11

TEXTBOX
20
10
200
28
Model Parameters
12
0.0
1

TEXTBOX
705
-10
885
8
Dynamics Monitoring
12
0.0
1

@#$#@#$#@
## WHAT IS IT?

This model simulates rumor and gossip propagation in organizational networks with adaptive trust dynamics. Based on Lu (2019), it explores how information spreads through social networks when agents have heterogeneous judgment abilities and dynamically update their trust in others based on information accuracy.

The model addresses the research question: **Under what conditions does a false rumor spread more widely than a true one, and how do structure, trust distributions, and interaction patterns affect whether it stabilizes as an accepted truth within an organization?**

Key features:
- **Heterogeneous agents**: Different judgment abilities and acceptance thresholds
- **Dynamic trust**: Trust evolves based on past accuracy of information sources
- **Network structures**: Random, small-world, or scale-free organizational networks
- **Verification events**: Rumors can be verified as true/false during simulation
- **Adaptive learning**: Trust update rule T_ij(t+1) = T_ij(t) + α(R_ij - T_ij(t))

## HOW IT WORKS

**Agent Properties:**
- `belief`: Current belief in the rumor (0-1 scale)
- `trust-table`: Dynamic trust values for each neighbor
- `judgment-quality`: Individual ability to assess information accuracy
- `acceptance-threshold`: Personal threshold for accepting rumors
- `times-heard`: Number of exposures to the rumor

**Spreading Mechanism:**
1. Agents who know the rumor attempt to share with random neighbors
2. Transmission probability depends on sender's belief level
3. Receivers update belief based on: trust in sender × sender's belief
4. Threshold-based acceptance: influenced by judgment quality and hearing frequency

**Trust Updating (every 10 ticks):**
1. Agents evaluate past messages from neighbors
2. Reinforcement signal R_ij = 1 if information was accurate, 0 otherwise
3. Trust adjusts: T_ij(t+1) = T_ij(t) + α(R_ij - T_ij(t))
4. After verification, agents know ground truth and update accordingly

**Dynamics:**
- Initial rapid growth phase as rumor spreads through network
- Saturation phase as network becomes fully informed
- Trust converges toward accurate assessment of reliable sources
- Heterogeneity amplifies spread; homogeneity dampens it

## HOW TO USE IT

**Setup Parameters:**
- `population-size`: Number of agents in the organization (10-500)
- `avg-degree`: Average number of connections per agent
- `initial-seeds`: Number of agents who initially know the rumor
- `network-type`: Choose organizational structure (random/small-world/scale-free)
- `rumor-is-true?`: Set whether the rumor is actually true or false

**Agent Heterogeneity:**
- `heterogeneity-level`: Standard deviation of judgment/threshold distribution (0-0.5)
- Higher values = more diverse agent characteristics

**Trust Dynamics:**
- `learning-rate`: Speed of trust adaptation (0-0.5, α in equations)
- `initial-trust-mean`: Average starting trust level (0-1)
- `initial-trust-sd`: Variation in initial trust (0-0.3)
- `trust-update-interval`: How often trust is recalculated (ticks)

**Rumor Mechanics:**
- `hearing-threshold`: Times agent must hear rumor before accepting (1-10)
- `verify-rumor?`: Enable verification event during simulation
- `verification-delay`: When verification occurs (ticks)

**Visualization:**
- `show-trust-links?`: Display link thickness/color based on trust
- Agent color: Red intensity = belief strength, gray = unaware
- Agent size: Larger = stronger belief

**Running:**
1. Click `Setup` to initialize the model
2. Click `Go` to run continuously, or `Step` for single tick
3. Monitor plots and statistics in real-time

## THINGS TO NOTICE

- **Two-phase dynamics**: Rapid initial spread, then saturation
- **Heterogeneity effect**: Higher heterogeneity → faster, wider spread
- **Trust evolution**: Watch how trust converges after verification
- **False vs True**: Compare spread patterns when `rumor-is-true?` changes
- **Network effects**: Small-world networks may show different patterns than random
- **Belief distribution**: Histogram shows consensus vs polarization

## THINGS TO TRY

1. **Compare true vs false rumors**: Run identical setups with only `rumor-is-true?` changed. Does the false rumor spread more widely? Why?

2. **Heterogeneity experiment**: 
   - Low heterogeneity (0.05) vs high (0.3)
   - Does heterogeneity amplify spread as Lu (2019) predicts?

3. **Network structure effects**:
   - Random vs small-world vs scale-free
   - Which structure allows false rumors to persist longer?

4. **Verification timing**: 
   - Early verification (50 ticks) vs late (400 ticks)
   - Can early verification stop a false rumor?

5. **Learning rate sensitivity**:
   - Fast learning (0.3) vs slow (0.05)
   - Does faster learning prevent false rumor stabilization?

6. **Trust initialization**:
   - High initial trust (0.8) vs low (0.3)
   - Does skepticism (low initial trust) protect against false rumors?

## EXTENDING THE MODEL

Possible extensions:
- **Source credibility**: Some agents have inherently higher credibility
- **Confirmation bias**: Agents preferentially trust sources aligned with prior beliefs
- **Multiple rumors**: Competing rumors about same topic
- **Forgetting**: Beliefs decay over time without reinforcement
- **Active skeptics**: Agents who actively counter false information
- **Cost of spreading**: Reputational cost for sharing false information
- **Homophily**: Agents preferentially connect with similar others
- **External media**: Broadcast channel that can verify/debunk rumors

## NETLOGO FEATURES

- **Table extension**: Used for sparse trust storage (only neighbors, not all agents)
- **Link-neighbor primitives**: Efficient network navigation
- **Scale-color**: Continuous color gradients for belief visualization
- **Dynamic network generation**: Three different topology algorithms
- **List operations**: Message history tracking with nested lists

## RELATED MODELS

- Virus on a Network (NetLogo Models Library)
- Diffusion on a Directed Network
- Preferential Attachment
- Small Worlds (Watts-Strogatz)

## CREDITS AND REFERENCES

**Based on:**
Lu, P. (2019). Heterogeneity, judgment, and social trust of agents in rumor spreading. Applied Mathematics and Computation, 350(C), 447–461. https://doi.org/10.1016/j.amc.2018.10.079

**Implementation:**
Extended Lu's model with:
- Dynamic trust updating based on information accuracy
- Verification events that reveal ground truth
- Multiple network topologies
- Enhanced heterogeneity mechanisms

**Model developed for:**
Advanced Topics in Programming - Final Project
Explores organizational gossip dynamics and conditions under which false rumors can spread more widely than true information.
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="false-vs-true-rumor" repetitions="20" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="500"/>
    <exitCondition>ticks &gt;= max-ticks</exitCondition>
    <metric>count turtles with [rumor-known?]</metric>
    <metric>count turtles with [rumor-known?] / population-size</metric>
    <metric>mean [belief] of turtles</metric>
    <metric>mean [belief] of turtles with [rumor-known?]</metric>
    <metric>count turtles with [belief &gt; 0.5]</metric>
    <metric>variance [belief] of turtles</metric>
    <metric>max [belief] of turtles</metric>
    <metric>min [belief] of turtles with [rumor-known?]</metric>
    <enumeratedValueSet variable="population-size">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="avg-degree">
      <value value="6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-seeds">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-type">
      <value value="&quot;small-world&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rumor-is-true?">
      <value value="&quot;true&quot;"/>
      <value value="&quot;false&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="heterogeneity-level">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="learning-rate">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-trust-mean">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-trust-sd">
      <value value="0.15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hearing-threshold">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trust-update-interval">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="verify-rumor?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="verification-delay">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show-trust-links?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-ticks">
      <value value="500"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="heterogeneity-effect" repetitions="15" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="500"/>
    <metric>count turtles with [rumor-known?] / population-size</metric>
    <metric>mean [belief] of turtles</metric>
    <metric>count turtles with [belief &gt; 0.5] / population-size</metric>
    <metric>ticks</metric>
    <enumeratedValueSet variable="population-size">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="avg-degree">
      <value value="6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-seeds">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-type">
      <value value="&quot;small-world&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rumor-is-true?">
      <value value="&quot;true&quot;"/>
      <value value="&quot;false&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="heterogeneity-level">
      <value value="0.05"/>
      <value value="0.1"/>
      <value value="0.15"/>
      <value value="0.2"/>
      <value value="0.25"/>
      <value value="0.3"/>
      <value value="0.35"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="learning-rate">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-trust-mean">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-trust-sd">
      <value value="0.15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hearing-threshold">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trust-update-interval">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="verify-rumor?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="verification-delay">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show-trust-links?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-ticks">
      <value value="500"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="network-structure-effect" repetitions="20" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="500"/>
    <metric>count turtles with [rumor-known?] / population-size</metric>
    <metric>mean [belief] of turtles</metric>
    <metric>count turtles with [belief &gt; 0.5]</metric>
    <metric>variance [belief] of turtles</metric>
    <enumeratedValueSet variable="population-size">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="avg-degree">
      <value value="6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-seeds">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-type">
      <value value="&quot;random&quot;"/>
      <value value="&quot;small-world&quot;"/>
      <value value="&quot;scale-free&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rumor-is-true?">
      <value value="&quot;true&quot;"/>
      <value value="&quot;false&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="heterogeneity-level">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="learning-rate">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-trust-mean">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-trust-sd">
      <value value="0.15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hearing-threshold">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trust-update-interval">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="verify-rumor?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="verification-delay">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show-trust-links?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-ticks">
      <value value="500"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="verification-timing" repetitions="15" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="600"/>
    <metric>count turtles with [rumor-known?] / population-size</metric>
    <metric>mean [belief] of turtles</metric>
    <metric>mean [belief] of turtles with [rumor-known?]</metric>
    <metric>count turtles with [belief &gt; 0.5] / population-size</metric>
    <metric>verified?</metric>
    <metric>verification-tick</metric>
    <enumeratedValueSet variable="population-size">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="avg-degree">
      <value value="6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-seeds">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-type">
      <value value="&quot;small-world&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rumor-is-true?">
      <value value="&quot;false&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="heterogeneity-level">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="learning-rate">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-trust-mean">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-trust-sd">
      <value value="0.15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hearing-threshold">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trust-update-interval">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="verify-rumor?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="verification-delay">
      <value value="50"/>
      <value value="100"/>
      <value value="150"/>
      <value value="200"/>
      <value value="300"/>
      <value value="400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show-trust-links?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-ticks">
      <value value="600"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="learning-rate-sensitivity" repetitions="15" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="600"/>
    <metric>count turtles with [rumor-known?] / population-size</metric>
    <metric>mean [belief] of turtles</metric>
    <metric>count turtles with [belief &gt; 0.5] / population-size</metric>
    <metric>variance [belief] of turtles</metric>
    <enumeratedValueSet variable="population-size">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="avg-degree">
      <value value="6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-seeds">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-type">
      <value value="&quot;small-world&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rumor-is-true?">
      <value value="&quot;false&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="heterogeneity-level">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="learning-rate">
      <value value="0.05"/>
      <value value="0.1"/>
      <value value="0.15"/>
      <value value="0.2"/>
      <value value="0.25"/>
      <value value="0.3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-trust-mean">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-trust-sd">
      <value value="0.15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hearing-threshold">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trust-update-interval">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="verify-rumor?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="verification-delay">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show-trust-links?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-ticks">
      <value value="600"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="initial-trust-effect" repetitions="15" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="500"/>
    <metric>count turtles with [rumor-known?] / population-size</metric>
    <metric>mean [belief] of turtles</metric>
    <metric>count turtles with [belief &gt; 0.5] / population-size</metric>
    <enumeratedValueSet variable="population-size">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="avg-degree">
      <value value="6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-seeds">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-type">
      <value value="&quot;small-world&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rumor-is-true?">
      <value value="&quot;true&quot;"/>
      <value value="&quot;false&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="heterogeneity-level">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="learning-rate">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-trust-mean">
      <value value="0.2"/>
      <value value="0.35"/>
      <value value="0.5"/>
      <value value="0.65"/>
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-trust-sd">
      <value value="0.15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hearing-threshold">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trust-update-interval">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="verify-rumor?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="verification-delay">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show-trust-links?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-ticks">
      <value value="500"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="time-series-dynamics" repetitions="10" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="500"/>
    <metric>ticks</metric>
    <metric>count turtles with [rumor-known?]</metric>
    <metric>count turtles with [rumor-known?] / population-size</metric>
    <metric>mean [belief] of turtles</metric>
    <metric>mean [belief] of turtles with [rumor-known?]</metric>
    <metric>count turtles with [belief &gt; 0.5]</metric>
    <metric>count turtles with [belief &gt; 0.7]</metric>
    <metric>variance [belief] of turtles</metric>
    <enumeratedValueSet variable="population-size">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="avg-degree">
      <value value="6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-seeds">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-type">
      <value value="&quot;small-world&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rumor-is-true?">
      <value value="&quot;true&quot;"/>
      <value value="&quot;false&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="heterogeneity-level">
      <value value="0.1"/>
      <value value="0.3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="learning-rate">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-trust-mean">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-trust-sd">
      <value value="0.15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hearing-threshold">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trust-update-interval">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="verify-rumor?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="verification-delay">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show-trust-links?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-ticks">
      <value value="500"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="full-factorial-analysis" repetitions="10" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="500"/>
    <metric>count turtles with [rumor-known?] / population-size</metric>
    <metric>mean [belief] of turtles</metric>
    <metric>mean [belief] of turtles with [rumor-known?]</metric>
    <metric>count turtles with [belief &gt; 0.5] / population-size</metric>
    <metric>variance [belief] of turtles</metric>
    <enumeratedValueSet variable="population-size">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="avg-degree">
      <value value="6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-seeds">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-type">
      <value value="&quot;random&quot;"/>
      <value value="&quot;small-world&quot;"/>
      <value value="&quot;scale-free&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rumor-is-true?">
      <value value="&quot;true&quot;"/>
      <value value="&quot;false&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="heterogeneity-level">
      <value value="0.1"/>
      <value value="0.2"/>
      <value value="0.3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="learning-rate">
      <value value="0.1"/>
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-trust-mean">
      <value value="0.4"/>
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-trust-sd">
      <value value="0.15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hearing-threshold">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="trust-update-interval">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="verify-rumor?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="verification-delay">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show-trust-links?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-ticks">
      <value value="500"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
