# Gforensics — The Build Plan

```text
VERSION   v3 — standalone
WRITTEN   2026-09-19
AGAINST   repo 7e931b6
STATUS    DISCUSSION DOCUMENT
          not agreed, not committed
```

**This file replaces v2 of the same name.** v2 was written as a list of
changes to the old plan, which meant you had to hold §13 of the context
doc in your head to read it. That was the wrong shape for the thing you
asked for. This version is the plan itself, standing on its own. The
change-log moved to Appendix A, where it belongs — still there, still
honest about what I altered, but no longer the front door.

---

## Contents

```text
 1  How we work together       ← read this first
 2  What we are building
 3  Where we are today
 4  The map
 5  PHASE 0   close out            ½–1 day
 6  PHASE 1   foundation           the long one
 7  PHASE 1.5 agent spike          1–2 days
 8  PHASE 2   evidence + agent
 9  PHASE 3   runnable by others
10  PHASE 4   credibility
11  What only you can do
12  Open calls — blocking
13  Risk register
14  The minimum shippable cut
15  Not in this plan
    Appendix A — what changed and why
    Appendix B — quick reference
```

---

# 1. How we work together

This is the part you asked for most, so it goes first and it is
specific. Not a sentiment — a loop, with a gate in it.

## 1.1 The division

```text
SARANSH                     CLAUDE
─────────────────────────────────────────────
architecture                implementation
validation                  boilerplate
domain reasoning            test scaffolding
the causal knowledge base   the machinery
                            around it
labelling                   mining automation
every architecture fork     every default
                            that is not a fork
```

The line is not "hard things / easy things". It is **irreplaceable /
replaceable**. Authoring a causal edge is irreplaceable — it encodes
what you know about GPUs and nobody can generate it for you. Writing a
NetworkX graph builder is replaceable and I should do it.

## 1.2 The loop, per step

```text
  1  DESIGN NOTE        [C]
       ≤ 25 lines, in the thread
       what it does
       its interfaces
       the decisions taken
       the alternatives rejected
       where I am guessing
              │
              ▼
  2  YOU AGREE OR REDIRECT   [S]   ← THE GATE
       I do not write code before this
              │
              ▼
  3  IMPLEMENT          [C]
              │
              ▼
  4  EXPLAIN-WITHOUT-SOURCE  [C]
       an ASCII block in docs/ that
       explains the module with the
       source file CLOSED
              │
              ▼
  5  YOU REVIEW         [S]
       against the design note,
       not against the diff
```

**Step 4 is your own rule made into an artifact.** You wrote: *if a
component can't be explained without reading the generated source, it
doesn't ship.* Right now that rule has no enforcement. This gives it
one — if I cannot write the block, the component is too complicated and
gets simplified before it lands.

**Step 5 matters more than it looks.** Reviewing a diff finds typos.
Reviewing against the design note finds the thing I quietly decided
without telling you, which is the failure mode you said you want to
avoid.

## 1.3 What a design note actually looks like

So you know what you are agreeing to, here is one for a step in
Phase 1:

```text
DESIGN NOTE — B2, Layer 1 topology graph

WHAT       builds an in-memory NetworkX graph of the
           fleet from normalized Events

KEYS       gpu:<uuid> and host:<pci_bus_id>
           NEVER hostname   ← Finding 4: the Hostname
           label is the container ID and the label set
           varies between exporters

TIME       every edge carries [t_start, t_end)
           ALLOCATED, HOSTED_BY, PEER_OF, ON_SWITCH
           a query without a time argument raises,
           it does not silently return "now"

DECIDED    rebuild from scratch per incident rather
           than maintain incrementally
           → slower, but no stale-state class of bug,
             and the fleet sizes we target make it
             irrelevant (2k GPUs ≈ 40ms)

REJECTED   persisting the graph
           → "pip install" beats "run a database"
             (Decision 2)

GUESSING   whether PEER_OF should be one edge or two.
           Going with one undirected until a query
           needs direction.
```

Twenty-two lines. You read it in a minute and either say go, or say
"no, PEER_OF is directed because rcv_err and rcv_remote_err
distinguish local from peer fault" — which is Finding 6, which I might
have missed, and which would have cost a refactor later.

## 1.4 Hands-on work

```text
ONE COMMAND BLOCK AT A TIME.

I give you a block.
You run it.
You paste the output.
Then, and only then, the next block.

Week 0 proved every environment differs
from what was assumed. Ten commands at
once means nine wasted.
```

## 1.5 The rule that will erode first

⚠ **This is R7 in the risk register and it is the one that ends
projects quietly.**

The first time a step gets implemented without a design note because it
"was obviously fine", the working model is over, and neither of us will
notice it happening. Not because anyone decided to abandon it — because
it was 11pm and the step was small.

If you ever want to skip the note for a step because it really is
mechanical, say so **per step**. I will skip it for that step and ask
again on the next one. What I will not do is start assuming.

---

# 2. What we are building

Included so this document stands alone. If you already have this
loaded, skip to §3.

## 2.1 The anchor

> Given a GPU-cluster incident, determine whether the root cause is
> **hardware or software**, and **which component** — with cited
> evidence, calibrated confidence, and a recommended remediation.

```text
Job crashed with NCCL timeout
  (NCCL = NVIDIA Collective
   Communications Library)
            ↓
    ┌───────┴───────┐
    ↓               ↓
software bug?   NVLink fault?
    ↓               ↓
restart job     cordon node,
                replace hardware

WRONG CALL COSTS REAL MONEY EITHER WAY
  a fault you keep rescheduling onto
  a healthy node you pull from the fleet
```

## 2.2 The architecture, in one block

```text
LAYER 1 — TOPOLOGY        LAYER 2 — CAUSALITY
what exists, right now    what causes what, in general

NetworkX, in-memory       versioned YAML
rebuilt from telemetry    reviewable in a pull request
changes constantly        changes almost never
instance-specific         universal domain knowledge
TIME LIVES ON EDGES       strength + source +
keys: UUID + pci_bus_id     corroborating +
                            contradicting + remediation

        ← THE PRODUCT IS LAYER 2 →
   Layer 1 is generated from whatever
   fleet you point at. Layer 2 is the
   thing nobody has published.
```

```text
DIAGNOSIS =
   walk Layer 1 to find WHO is involved
 → walk Layer 2 to find WHY
 → score deterministically
 → if ambiguous, the agent fetches more
   evidence and the scorer RE-RUNS
```

## 2.3 The property everything hangs on

```text
  LLM CHOOSES THE PATH
  DETERMINISTIC LAYER PRODUCES THE VERDICT

  enforced by SCHEMA VALIDATION, not by
  prompting

AGENT MAY              AGENT MAY NOT
─────────────────────────────────────────
choose next tool       assign confidence
decide sufficiency     name a cause outside
decide INsufficiency     the candidate set
group events           cite evidence that is
phrase explanation       not a real ID
                       execute remediation
```

If the validator is weak, this whole claim is decoration. That is why
step 2.4 is load-bearing and is never cut.

## 2.4 The three-state event schema

The project's central empirical claim, and the thing Week 0 validated
three separate times.

```text
nvlink_crc_flit_err on GPU-042, link 7

  MEASURED_PRESENT   value 14, and rising
  MEASURED_ABSENT    value 0, counter readable
  NOT_MEASURED       NVMLError_NotSupported
                       ← Finding 13, all 24 links

A diagnoser that folds the third state into the
second concludes:

  "NVLink counters are zero
   → NVLink is healthy
   → the NCCL timeout is a software problem"

Confidently wrong. And it is EXACTLY the
misleading-symptom case this project exists to
get right.
```

## 2.5 Hard boundaries

```text
✗ NEVER writes to the fleet. Recommends only.
  Never cordon, never restart, never RMA.
  A human acts.

✗ No judgement model. The LLM does not grade
  its own output.

✗ Simulator and diagnoser never share a rules
  file. Enforced in CI (continuous integration).
```

---

# 3. Where we are today

```text
REPO   github.com/SARPAT/Gforensics @ 7e931b6
       7 commits · ZERO lines of Python
```

```text
EXISTS                        PAPER ONLY
─────────────────────────────────────────────
README (2 lines)              src/gfd/**
LICENSE (Apache-2.0)          causal-kb/**
.gitignore                    simulator/**
scripts/scrub_captures.sh     eval/**
data/captures/scrubbed/       CI workflows
  19 telemetry files          pyproject.toml
  sessions 1 and 2            docs/**
  findings 1–17               dashboard/
```

```text
DESIGN                        EVIDENCE
─────────────────────────────────────────────
11 decisions settled ✓        Week 0 Day 1 ✓
two-layer split ✓               session 1
scoring: 6 terms and            Lightning AI
  3 constraints locked ✓        1× A100-40GB
  form of combine() OPEN ⚠      driver 570.148.08
agent boundaries fixed ✓        session 2
eval axes A1–A4 fixed ✓         Modal
repo structure drafted ✓        2× A100-80GB
                                driver 580.95.05
                              findings 1–17 ✓
                              scrubbing verified ✓

                              Week 0 Day 2 ⬜
                              Tier-1 mining
                              IN FLIGHT, 6 items
                              awaiting your call
```

**The honest summary.** The thinking is a long way ahead of the code,
which is the correct order given how you work. But the gap is now wide
enough that the next mistake is expensive, because nothing written so
far has been tested against a program that runs.

---

# 4. The map

```text
PHASE 0   close out Week 0            ½–1 day
   │      scrubber defect, repo skeleton,
   │      Tier-1 decisions
   ▼
PHASE 1   FOUNDATION — no LLM at all  the long one
   │      two lanes running in parallel
   │      LANE A [S] causal KB
   │      LANE B [C] machinery
   ▼
PHASE 1.5 AGENT SPIKE                 1–2 days
   │      test the central claim CHEAP,
   │      before building on it
   ▼
PHASE 2   EVIDENCE + AGENT
   │      tools, loop, validator, abstention
   ▼
PHASE 3   RUNNABLE BY OTHERS
   │      webhook, adapter, CLI, demo
   ▼
PHASE 4   CREDIBILITY
          break the seal, publish honest numbers
```

**Phases, not weeks.** A gate says what must be TRUE to proceed, not
what day it is. See Appendix A, change C1, for why.

---

# 5. PHASE 0 — close out Week 0

**Goal:** nothing half-finished is carried into the build.

## 5.1 Steps

| # | Step | Owner |
|---|---|---|
| 0.1 | Fix the `scrub_captures.sh` container-ID rule, regenerate captures | [C→S] |
| 0.2 | Commit the context doc as `docs/PROJECT_CONTEXT.md` | [C] |
| 0.3 | Correct two defects in that doc before committing | [C→S] |
| 0.4 | Decide the six Tier-1 gating items | [S] |
| 0.5 | Mine Tier-1, split at mine time, label by hand | [S→C] |
| 0.6 | Repo skeleton: `pyproject.toml`, ruff, mypy, pytest, CI | [C] |

## 5.2 On 0.1 — the scrubber defect 🔴

```text
THE RULE
  s/(^|[^-0-9a-f])[0-9a-f]{12}([^-0-9a-f]|$)/…/g

It matches ANY 12-character hex run, so it is
eating real telemetry in four places:

  proc_nvidia_gpus.txt      DMA Mask
  kmsg_sample.txt           max_idle_ns
  modal_nccl_debug_head     ×2

THE WORST ONE
  /sys/devices/system/node/node4294967295/cpumap
                           ↓
  /sys/devices/system/node/noCONTAINERID00/cpumap

  4294967295 = 0xFFFFFFFF = (uint32) −1
             = the "no NUMA node" sentinel
```

⚠ That is the same all-ones-means-unknown pattern as Finding 12, from a
third source. It arguably deserves a number of its own as Finding 18 —
your call, since findings are your record.

The script's own header says *"scrubbing is deliberately NARROW;
telemetry values must survive untouched."* So this is a defect against
a stated contract, not a tradeoff. Two of the four hits have been
present since `7908dd3`.

```text
FIX DIRECTION — needs your call
  A  require ≥1 a–f character
     ✓ kills the pure-decimal false positive
     ✗ a real container ID can be all digits
  B  anchor to where container IDs actually
     appear (the Hostname label, cgroup paths)
     ✓ precise
     ✗ more rules to maintain
  C  both

  My recommendation: C. The cases are cheap
  and the cost of a silent corruption is a
  capture file nobody trusts.
```

## 5.3 On 0.3 — two defects in the context doc

```text
DEFECT 1 — §14 counts FOUR instances of
  measured-absent vs not-measured.
  Your README counts THREE (findings 2, 3, 13).

  ✓ THE README IS RIGHT.
    §14 gets to four by adding Finding 17, but
    17 is topology FABRICATED and reported as
    fact — a different failure mode from a
    signal going silent.

  → fix the doc to match the README,
    not the reverse

DEFECT 2 — §15 says nobody publishes on
  rule-out reasoning, while citing Meta as the
  source for exactly that.

  The source chat quotes Meta's differential
  diagnosis framing at line 1577 and builds
  contradicting_signals ON it, deliberately.
  The doc then replaced the real citation
  ("Meta reliability paper — PCIe errors
  co-occur with XID 79 and IPMI critical
  interrupts") with "<literature citation>".

  → restore the citation, and rewrite the
    novelty claim so it is not
    self-contradicting
```

⚠ Committing the doc matters for a reason beyond tidiness: right now
the project's design lives only in the chat and in project files, so
the repo and the design can drift apart silently and nobody will see it
in a diff.

## 5.4 On 0.4 and 0.5 — Tier-1 ground truth

Six items are open in the Day-2 thread. Two of them block this phase.
They are summarised in §12; the thread has the full argument.

```text
DIVISION, already settled in the chat and
not changing:

  MINING    automated   [C]
  LABELLING manual      [S]
```

⚠ The chat's own note stands: *Day 2's mining is slow, manual work and
it will feel unproductive compared to writing code. It is the single
highest-leverage day in the entire project.* Every evaluation number
published later rests on whether those labels are real.

## 5.5 Gate 0 → 1

```text
□ scrubbed captures are clean AND telemetry
  survived — verified by diffing against raw
□ context doc committed, both defects fixed
□ Tier-1 inclusion rule frozen
□ dev/test split made, test split SEALED
□ symptom→class map frozen, if you take GT-2
□ repo builds, CI green on an empty suite
```

---

# 6. PHASE 1 — foundation, no LLM at all

**Goal:** deterministic diagnosis works end to end on a simulated
incident, and you know what the baselines score.

Two lanes, in parallel. This is the biggest change from the original
plan — see Appendix A, C2.

```text
LANE A [S] — causal knowledge      LANE B [C] — machinery
─────────────────────────────────────────────────────────────
A1  seed KB: ECC + NVLink  ──────→ B1  schemas
       │                                 │
       ▼                                 ▼
A2  remaining 6 classes            B2  Layer 1 graph
       │                                 │
       ▼                                 ▼
A3  signals/xid.yaml               B3  simulator
       │                                 │
       ▼                                 ▼
A4  remediation vocabulary   ────→ B4  scenario engine
                                         │
                                         ▼
                                   B5  correlation
                                         │
                                   Q1 ──▼
                                   B6  scorer
                                         │
                                         ▼
                                   B7  baselines B0–B3
```

## 6.1 Lane A — the causal knowledge base [S]

**This is the product. It is also the only work in the project that
cannot be delegated to me.**

| # | Step | Produces |
|---|---|---|
| A1 | Seed: ECC + NVLink | `classes/ecc.yaml`, `classes/nvlink.yaml` |
| A2 | Remaining six classes | `classes/{pcie,gpu-off-bus,thermal-power,nccl,driver-cuda,scheduler-node-health}.yaml` |
| A3 | XID signal catalog | `signals/xid.yaml`, `signals/dcgm-fields.yaml`, `signals/job-signals.yaml` |
| A4 | Remediation vocabulary | `remediation/actions.yaml` |

### Why A1 comes first and is only two classes

I cannot write B1 (the schemas) against nothing. I need real authored
edges to design against, and ECC plus NVLink between them exercise
nearly every field the schema needs:

```text
ECC                        NVLINK
──────────────────────────────────────────────
per-location fields        non-contiguous per-link
  (L1, L2, device,           field indices
   register, texture,        (l0–l5 then l12–l14)
   shared, CBU, SRAM)        → parsers must not
                               loop 0..N  (Finding 6)
a DEGRADATION LADDER       a CONTRADICTING signal
  remap_rows_avail_          recovery_successful
  {max,high,partial,           rules OUT persistent
   low,none}                   hardware fault
  → monotonic, not binary      (Finding 6)
  → precursor signal
                           a NOT_MEASURED case
different remediation        NotSupported on all
  per location               24 links (Finding 13)
  SRAM ECC (Xid 94,
   contained) ≠ DRAM
   double-bit (Xid 48)
  (Finding 5)
```

Maybe half a day of your time. Everything in Lane B binds to it.

### What an edge looks like, with the two new fields

```yaml
# causal-kb/classes/nvlink.yaml
- id: nvlink-persistent-link-fault
  cause: NVLink persistent link fault
  symptom: nccl_collective_timeout
  strength: moderate

  source: "DCGM field reference 1200-1215;
           capture finding 6"

  applies_to: [A100, H100, B200, GB200]   # ← NEW, C6

  corroborating_signals:
    - nvlink_crc_flit_err_rising
    - nvlink_recovery_failed
    - nvlink_symbol_ber_elevated

  contradicting_signals:
    - nvlink_recovery_successful   # transient, not
                                   # persistent (F6)
    - nvlink_rcv_remote_err_only   # the PEER's fault
    - nvlink_buffer_overrun_only   # congestion, not
                                   # hardware (F6)
    - nccl_transport_is_p2p        # finding 14

  remediation:                            # ← NEW, C6
    - when: [nvlink_recovery_failed]
      action: cordon_node
      bucket: immediate
      source: "NVIDIA XID doc, Resolution Bucket"
    - when: [nvlink_symbol_ber_elevated]
      unless: [nvlink_recovery_failed]
      action: monitor_ber_trend
      bucket: investigatory
```

```text
NOTE THE TWO NEW FIELDS. Both come out of the
XID catalog, neither is in the original design.

applies_to    XID 13 is valid on A100 and
              "Unused" on GB200. An edge with no
              applicability field is simply wrong
              on some fraction of any real fleet.

remediation[] XID 154 is a RECOVERY-ACTION XID
              that other XIDs defer to. A flat
              string cannot express "if 154 is
              also present, wait for recovery
              before cordoning."

Retrofit cost: one edit per authored file.
At 2 classes ≈ free. At 8 classes plus signals
it is a tedious day with a real chance of drift.
That is why they land NOW.
```

⚠ `contradicting_signals` is the part most systems omit, and it is why
the architecture can rule things out instead of only accumulating
support. Real diagnosis is mostly elimination.

⚠ Where an edge's source is `author judgement`, say so. A knowledge
base where weak edges are **labelled** weak is worth more than one
pretending to uniform confidence.

## 6.2 Lane B — the machinery [C]

| # | Step | Produces | Depends on |
|---|---|---|---|
| B1 | Pydantic schemas | `src/gfd/schemas/` + `causal-kb/schema.json` | A1 |
| B2 | Layer 1 topology graph | `src/gfd/graph/` | B1 |
| B3 | Simulator core | `simulator/{fleet,topology_gen,workload_gen,telemetry_gen}.py` | B1 |
| B4 | Scenario engine | `simulator/scenarios/`, `simulator/perturbations/` | B3, A2 |
| B5 | Correlation engine | `src/gfd/correlation/` | B2 |
| B6 | Scorer | `src/gfd/scoring/` | **Q1** |
| B7 | Baselines B0–B3 | `eval/baselines/`, `eval/harness.py` | B6, B4 |

### B1 — schemas

```text
Event        three-state, per §2.4
Entity       keyed UUID + pci_bus_id, NEVER
             hostname (Finding 4)
Incident     a group of Events
Evidence     typed, with an ID the validator
             can check
Hypothesis   candidate + per-term scores
Diagnosis    cause, confidence, evidence[],
             alternatives, sources[], cost
Outcome      designed NOW even though unused
             until v3 — retrofitting is
             impossible (Decision 10)
```

### B4 — the isolation guard goes in HERE, not later

```text
SIMULATOR side          DIAGNOSER side
────────────────────────────────────────────
how OFTEN things fail   what CAUSES what
seeded from             authored from
  Meta HPCA 2025          NVIDIA XID catalog
  Minder Table 1          DCGM docs
                          NCCL docs
simulator/distributions/  causal-kb/

  CI FAILS if either imports the other.
```

This is Risk 1. Without it the evaluation is circular and every number
downstream is worthless.

### B6 — the scorer, blocked on you

```text
score = combine(
    prior_strength,    ← from the YAML
    local_evidence,    ← learned, n-weighted
    corroboration,     ← signals present
    contradiction,     ← signals absent/opposing
    temporal_proximity,
    topology_match
)

THREE CONSTRAINTS — settled, not open
  1  PRIOR AND POSTERIOR STORED SEPARATELY
       always show both, always roll back,
       "why did it change?" is answerable
  2  EVERY TERM'S CONTRIBUTION RECOVERABLE
       not a black box
  3  n IS ALWAYS VISIBLE
       "0.85 → 0.73 over 200 incidents"
       vs "…over 3 incidents"  ← ignore

ONLY THE FORM OF combine() IS OPEN.
That is Q1, and it is your call.
```

### B7 — baselines

```text
B0  symptom → cause lookup table
B1  LLM on raw telemetry, no structure
B2  LLM + retrieval, no graph
B3  deterministic pipeline, no LLM
    ← the one that matters; if the agent
      never beats B3 the thesis is wrong
```

## 6.3 Gate 1 → 1.5

```text
□ causal KB covers 8 classes, every edge
  carries a source
□ deterministic diagnosis runs end to end
  on a simulated incident
□ B0–B3 have a TIER-3 score on the
  misleading-symptom subset
□ isolation check green in CI
□ every module has its
  explain-without-source block
```

⚠ **Read that third line carefully.** It says Tier-3. At this point
Tier-1 is sealed and Tier-2 does not exist, so the only number
available is synthetic cases from a generator you wrote, scored against
a knowledge base you authored. It is a useful regression baseline. It
is not evidence about the world, and the gate must not be worded as if
it is. (The original plan's exit criterion said "you know B3's score on
the misleading-symptom subset" — full stop — which walks straight into
the doc's own warning about the number that means nothing.)

---

# 7. PHASE 1.5 — the agent spike

**1–2 days. Optional — this is Q3. It is the change I would argue for
hardest.**

## 7.1 The problem it solves

```text
THE ORIGINAL ORDER

  Week 1  build all the deterministic machinery
  Week 2  build the full agent
  W2 D7   ← THE FIRST TIME you learn whether
            the agent beats deterministic
  Week 3  make it runnable
  Week 4  publish

If the answer at W2 D7 is "no meaningful gain",
you are HALFWAY through the calendar with the
project's central claim unsupported, and the
remaining half is packaging.
```

The context doc's answer to this is *"that's the experiment working,
not failing — plan to report it either way."* That is intellectually
correct and operationally useless. You still spent two weeks first.

## 7.2 The move

```text
Week 0 worked because you REFUSED to design the
schema against imagination. You rented a GPU and
looked at what actually came out.

The "agent beats deterministic" claim is exactly
as unvalidated right now as the telemetry schema
was then.

So: apply the same move to the architecture.
```

## 7.3 What gets built

```text
INPUT     seed KB from A1 (2 classes)
          scorer from B6
          Tier-3 misleading subset from B4

BUILD     the THINNEST agent that can exist
            ONE tool: get_contradicting()
            budget: 2 calls
            no retrieval, no history
            no validator, no prompts directory
            ~100 lines

MEASURE   separation gained vs B3
          on ~30 constructed-ambiguous cases

READ      the DIRECTION and rough size.
          Not a publishable number.
```

## 7.4 Reading the result

```text
OUTCOME                   MEANING            ACTION
──────────────────────────────────────────────────────
clear gain                thesis has legs    Phase 2
                                             as planned

no gain, BUT the extra    mechanism right,   Phase 2, but
evidence DID separate     scorer is not      fix the scorer
the hypotheses            reacting to it     FIRST

no gain AND no            one more signal    REDESIGN
separation                may not be able    before
                          to resolve these   investing
                          candidates
```

```text
✅ cost is 1–2 days of MY time
✅ reuses the seed KB and scorer you needed
   anyway — nothing is thrown away except
   ~100 lines of loop code
⚠ HONEST RISK: a thin agent on 2 classes could
  show no gain for reasons that disappear at 8,
  and you talk yourself out of a good design on
  the strength of a bad spike.
  → the guard is the three-row table above.
    "No gain" alone is NOT the signal.
    "No gain AND no separation" is.
```

## 7.5 Gate 1.5 → 2

```text
□ you have SEEN the direction of the agent
  effect before Phase 2's cost is committed
```

---

# 8. PHASE 2 — evidence + agent

**Goal:** you know whether the agent beats deterministic-alone on
ambiguity, on synthetic cases and on the dev split of real ones.

| # | Step | Owner |
|---|---|---|
| 2.1 | Knowledge corpus + retrieval | [C] |
| 2.2 | Tool layer, evidence objects with IDs | [C] |
| 2.3 | Agent loop, budgets, abstention | [C] |
| 2.4 | Output validator + retry-once | [C] |
| 2.5 | Case-based retrieval | [C] |
| 2.6 | Outcome endpoint + store | [C] |
| 2.7 | Ablation B0–B4, four axes | [C→S] |

## 8.1 The tool set

```text
READ TELEMETRY          TRAVERSE LAYER 1
  get_events              get_topology
  get_gpu_health          get_peers
  get_job_logs            get_cohabitants
  get_dcgm_fields         get_switch_members
                          get_jobs_on

CAUSAL KNOWLEDGE        RETRIEVAL
  get_causes_for          search_docs
  get_corroborating       lookup_xid
  get_contradicting ★

HISTORY                 SCORING (deterministic)
  find_similar_incidents  score_hypotheses
  get_entity_history      check_separation
  get_repair_history

★ the one most implementations omit

NOT TOOLS, DELIBERATELY
  ✗ run_arbitrary_query   ✗ cordon_node
  ✗ execute_command       ✗ set_confidence
```

**Design principle:** tools return evidence objects with IDs, never
free text — so the agent can cite them and the validator can verify the
citation.

## 8.2 Loop control

```text
agent picks tool → evidence added →
score_hypotheses() → check_separation()

  separated?   → DONE
  budget out?  → ABSTAIN
  else         → next tool

HARD CAPS
  8 tool calls · 30s wall clock
  1 retry on schema violation

BUDGET EXHAUSTED = ABSTAIN.
Not "best guess anyway."
```

## 8.3 On 2.4 — the validator 🔴

```text
CHECKS, on every diagnosis
  □ root cause ∈ candidate set?
  □ every evidence ID real?
  □ confidence came from the SCORER, not
    from the model?
  → reject and retry ONCE, then abstain

This is what makes "the LLM cannot
hallucinate a root cause" a property by
CONSTRUCTION rather than a hope.

It is never cut. Not under any schedule
pressure.
```

## 8.4 On 2.1 — corpus licensing

```text
NVIDIA docs can be FETCHED and indexed
locally. They cannot be bulk-committed.

  knowledge/fetch_sources.py    ✓ ships
  knowledge/sources.yaml        ✓ ships
  knowledge/runbooks/           ✓ ships (ours)
  knowledge/index/              ✗ gitignored
```

## 8.5 Gate 2 → 3

```text
□ you KNOW whether the agent beats
  deterministic on ambiguity — on Tier-3 AND
  the DEV split of Tier-1
□ if it does NOT, that is written down, and
  Phase 3 proceeds with the claim corrected
  rather than dropped
□ the TEST split is still sealed and UNREAD
```

---

# 9. PHASE 3 — runnable by others

**Goal:** a stranger with no GPU can evaluate this in five minutes.

| # | Step | Owner | Cut? |
|---|---|---|---|
| 3.1 | FastAPI + Alertmanager webhook | [C] | core |
| 3.2 | DCGM adapter, validated against Week-0 captures | [C→S] | core |
| 3.3 | CLI — `gforensics diagnose GPU-042` | [C] | core |
| 3.4 | docker-compose demo fleet | [C] | core |
| 3.5 | Minimal dashboard | [C] | ✂ |
| 3.6 | Slack integration | [C] | ✂ |
| 3.7 | Ops: logging, health, config, metrics | [C] | partial |

## 9.1 On 3.1 — why webhook-first

```text
"Point your Alertmanager at this"
  = a 5-minute adoption story.

We consume THEIR alert rather than
reinventing detection. Log tailing is
secondary. (Decision 5)
```

## 9.2 On 3.2 — where Week 0 pays off

The adapter is validated against the 19 real capture files, not against
the simulator. Each finding becomes a test case:

```text
Finding 1   XID field is a GAUGE of the last
            Xid, not a counter
            → the adapter must NOT count events;
              bursts collapse

Finding 2   dcgm-exporter drops unsupported
            fields SILENTLY
            → absent field ≠ zero → NOT_MEASURED

Finding 3   violation counters read 0 while the
            condition is ACTIVE
            → zero ≠ healthy

Finding 4   the Hostname label is the container
            ID and the label set varies
            → never key on it

Finding 13  NVMLError_NotSupported on all 24
            NVLink links
            → NOT_MEASURED, not zero

Finding 14  "Using network Socket" with 12
            NVLinks active
            → transport truth lives in
              "type NVL/…" and "via P2P/…"
            → a parser keying on "Using network"
              produces FALSE NVLink-fault
              diagnoses
```

⚠ Finding 14 is the archetype of the whole project: the loudest line in
the log points at the wrong component. It is also, for the record, a
case that can never be Tier-1 ground truth, because the label is yours.

## 9.3 Gate 3 → 4

```text
□ a stranger with no GPU evaluates the
  project in five minutes
□ that has been TESTED on an actual person
  who is not you
```

---

# 10. PHASE 4 — credibility

**Goal:** honest numbers, failures included, and a repo an operator can
adopt.

| # | Step | Owner |
|---|---|---|
| 4.1 | **Break the seal.** Tier-1 test split, run ONCE | [C→S] |
| 4.2 | Calibration curves + ECE (Expected Calibration Error) | [C] |
| 4.3 | Degradation matrix | [C] |
| 4.4 | `EVALUATION.md`, including the failures | [C→S] |
| 4.5 | Causal KB docs + contribution guide | [S→C] |
| 4.6 | README, ARCHITECTURE, limitations | [C→S] |
| 4.7 | Publish | [S] |

## 10.1 On 4.1 — once means once

```text
The split was sealed at mine time so that this
number means something.

If the result disappoints, THAT IS THE RESULT.
Re-running after a tweak is exactly how sealed
splits stop being sealed, and it happens by
accident, not by decision.
```

## 10.2 On 4.4 — the paragraph that is currently written nowhere

```text
NVLink's share of hardware faults:

  ByteDance / Minder Table 1   1.7%
  Lablup 504-GPU study (2026)  DOMINANT
                               (XID 145/149)

TWO PUBLISHED FLEETS DISAGREE ABOUT THE SAME
COMPONENT BY AN ORDER OF MAGNITUDE.
```

That turns "fleets need locally-adapted posteriors" from an assumption
into a **cited disagreement between two published fleets**. It is one
of the strongest paragraphs available to this project and it exists in
no document today.

⚠ It also independently confirms a Week-0 refinement of yours: Minder
names "PCIe downgrading" as a 6.6% class of its own, which is the
degradation-not-binary pattern you already argued for.

## 10.3 The four axes

```text
A1  CALIBRATION      does 0.8 confidence mean
                     right 80% of the time?
A2  DEGRADATION      what happens as signals
                     are removed?
A3  MISLEADING       the architecture test
    SYMPTOMS         ← the money metric
A4  ABSTENTION       does it know when it
                     does not know?
```

⚠ **The number that means nothing:** overall accuracy on synthetic
cases from your own generator. Report it, but never lead with it.

## 10.4 Two metrics operators ask for that we would forget

```text
COST PER DIAGNOSIS
  tokens + tool calls + wall clock
  → decides whether it can run on EVERY alert
    or only on escalations

TIME TO DIAGNOSIS vs HUMAN BASELINE
  → the actual value proposition
```

## 10.5 Gate 4 → done

```text
□ honest numbers, failures included
□ an operator can adopt it
□ causal-kb/ is usable WITHOUT our code
```

That last one is the test of whether this became infrastructure or a
demo. Someone should be able to consume the YAML in their own tooling
and never run a line of our Python.

---

# 11. What only you can do

```text
IRREPLACEABLE — no amount of my time substitutes

  ▸ authoring the causal KB          Lane A
  ▸ labelling Tier-1 cases           0.5
  ▸ the form of combine()            Q1
  ▸ the six Day-2 calls              0.4
  ▸ every design-note gate           §1.2 step 2
  ▸ judging the spike                1.5.3
  ▸ the scrubber fix direction       0.2

NEEDS YOUR ACCOUNTS OR YOUR MONEY

  ▸ any further GPU capture
      still outstanding, needs bare metal
      and root:
        a real Xid line from a LIVE fault
        populated NVLink error counters
        multi-GPU nvidia-smi topo -m
        NVSwitch / fabric-manager telemetry
  ▸ publishing decisions

NEEDS A HUMAN WHO IS NOT ME

  ▸ Gate 3's five-minute test
```

⚠ On the outstanding captures: both providers used so far (Lightning
AI, Modal) are sandboxed and preclude longitudinal capture. That
constraint is already noted in the repo. It means the precursor-signal
work (Finding 5's remap-row ladder, the Lablup claim that XID
precursors are observable before failure) cannot be validated on
rented sandbox GPUs at all. Worth knowing before spending on another
session expecting it to close that gap.

---

# 12. Open calls — blocking

## Q1 — the form of `combine()` 🔴

Blocks B6, which blocks B7 and the spike.

```text
A  WEIGHTED SUM
   score = Σ wᵢ · termᵢ
   ✅ trivially decomposable
   ✅ every contribution recoverable
   ✅ easiest to explain in one line
   ⚠ contradiction can only SUBTRACT linearly
   ✗ a hard contradiction should be able to
     KILL a hypothesis, and this cannot

B  NOISY-OR ON SUPPORT,
   MULTIPLICATIVE ON CONTRADICTION
   support = 1 − Π(1 − sᵢ)
   score   = support · Π(1 − cⱼ)
   ✅ contradiction CAN zero a hypothesis
   ✅ still fully decomposable per term
   ✅ matches "diagnosis is mostly elimination"
   ⚠ harder to explain in one sentence
   ⚠ needs contradiction STRENGTHS, not just
     present/absent → more authoring on Lane A

C  LOG-ODDS SUM
   ✅ principled; terms add as evidence
   ✅ prior/posterior split falls out naturally
   ⚠ every term must be expressed as a
     likelihood ratio
   ✗ biggest authoring burden on YOUR lane,
     and the burden lands before you know
     whether it was worth it
```

```text
MY RECOMMENDATION: B

"Real diagnosis is mostly elimination" is this
project's own thesis. A cannot express
elimination. C can, but charges your lane for
the privilege before you have any evidence the
extra precision pays.

But this is genuinely your call — it changes
what you have to author, and I am not going to
pick something that spends your time.
```

## Q2 — do you take the dev/test seal?

Blocks 0.5. Full argument in the Day-2 thread; the short version:

```text
D2 reads ~30 real incidents
     ↓
W1 authors the causal KB from them
     ↓
W4 evaluates on those same 30

That is test-set leakage. The CI isolation guard
does NOT catch it, because no file is shared —
the guard passes and the number is still
uninterpretable.

FIX  split at MINE time, before reading
       dev  ~1/3   may inform the KB
       test ~2/3   SEALED until 4.1

⚠ cost: headline N drops from ~30 to ~20
✅ I take it anyway — an unsealed Tier-1
   number is not a weaker number, it is not
   a number
```

## Q3 — do you take the agent spike?

1–2 days of my time. §7 has the full case. If you decline, the plan
works without it and I will not raise it again.

## Q4 — full-time, or evenings and weekends?

Changes nothing in the content. Changes what I treat as realistic, and
whether I should be pushing the cut in §14 harder than I currently am.

---

# 13. Risk register

| # | Risk | Guard | Where |
|---|---|---|---|
| R1 | Circular ground truth | separate provenance, CI-enforced | B4 |
| R1b | **Eval set leaks into the KB** | dev/test split, sealed | Q2 |
| R2 | Nobody can run it | simulator ships as a product | B3, 3.4 |
| R3 | Confident wrong diagnosis | validator + abstention | 2.4 |
| R4 | Feedback poisoning | priors never overwritten; human gates structural change | B6 |
| R5 | Scope creep | the cut in §14 | §14 |
| R6 | **Agent adds nothing** | spike before investment | §7 |
| R7 | **Discuss-first erodes** | design-note gate | §1.2 |

R1b, R6 and R7 are not in the original risk list.

```text
R7 IS THE ONE THAT ENDS PROJECTS QUIETLY.

Not by anyone deciding to abandon the working
model — by one step being implemented without
a design note because it was late and the step
was small, and then the next one, and then it
is just how we work.
```

---

# 14. The minimum shippable cut

Agreed NOW, used only if time runs short. Deciding this while tired and
attached to the work is how scope collapses instead of being cut.

```text
SHIPS NO MATTER WHAT
  Phases 0, 1, 2 complete
  3.1 webhook   3.3 CLI   3.4 demo fleet
  4.1 sealed evaluation
  4.4 EVALUATION.md
  4.6 README + limitations

CUT FIRST, IN THIS ORDER
  1  3.6  Slack
  2  3.5  dashboard
  3  4.3  degradation matrix
  4  2.5  case-based retrieval
  5  2.1  retrieval corpus
          ← the biggest cut. The agent loses
            search_docs and keeps every other
            tool. Survivable; nothing else
            structural depends on it.

NEVER CUT
  ▸ the isolation guard          R1
  ▸ the output validator         2.4
  ▸ the sealed split             Q2
  ▸ EVALUATION.md's failures section

Those four are the entire difference between
a credible repo and a demo.
```

⚠ Note where the risk actually sits: **all the technical risk is in
Phases 1 and 2.** Phases 3 and 4 are roughly half the calendar and
maybe a fifth of the risk. If time slips, it slips there, and this list
is what makes that a decision rather than an accident.

---

# 15. Not in this plan

```text
✗ LEMON-NODE DETECTION
    comes free once the graph holds incident
    history. Highest operational value,
    weakest technical case. After v1.

✗ WEIGHT LEARNING (v5, n ≥ 200)
    ARCHITECTED for in B6 — the three
    constraints exist precisely so this can
    be added without a rewrite.
    Not BUILT in this plan.

✗ NEO4J OR ANY DATABASE
    "pip install" beats "run a database".
    Adoption friction is the enemy.

✗ A JUDGEMENT MODEL
    rejected, and the rejection stands.
    (The model it was considered against was
     Jev / TypeSafe — kept named here so the
     rejection stays checkable.)

✗ ANY WRITE PATH TO THE FLEET
    recommend only. Permanently. This is not
    a v2 feature.
```

---

# Appendix A — what changed from the original plan, and why

The original is §13 of `GFORENSICS_PROJECT_CONTEXT.md`. Nine changes.
Three are structural.

## C1 — weeks became phases with gates

```text
BEFORE              AFTER
────────────────────────────────────
Week 1, D1…D7       Phase 1, steps
calendar-bound      gate-bound
```

You flagged the calendar risk yourself early in the chat — final year,
job search, other projects. A 4×7 plan is 28 full working days; on
evenings and weekends it is closer to ten weeks. A plan that says
"Week 2 D3" when you are on calendar week six stops being a tool and
becomes a source of guilt.

⚠ Tradeoff accepted: gates without dates can drift forever. §14 is the
counterweight.

## C2 — the causal KB became a parallel lane 🔴

```text
BEFORE   Week 1 D5 — one day of seven,
         while being described in the same
         breath as "SLOWEST, HIGHEST VALUE"

AFTER    Lane A, spanning all of Phase 1
```

Three reasons, in order of force:

```text
1  IT IS YOUR WORK AND I CANNOT DO IT.
   Giving your irreplaceable work one day
   and my replaceable work six is backwards.

2  EVERYTHING BINDS TO IT.
   The scorer reads it. The tools read it.
   The agent's candidate set comes from it.
   The eval measures against it. Late
   authoring means everything gets built
   against a placeholder and then revised.

3  IT IS THE PRODUCT.
   §4 says Layer 2 is the thing nobody has
   published. A repo with a thin KB and a
   thick agent has built the commodity half.
```

## C3 — new Phase 1.5, the agent spike 🔴

Full case in §7. In one line: test the project's central claim at ~30%
of the calendar instead of 50%, for 1–2 days of my time, reusing
artifacts you needed anyway.

## C4 — Phase 1's exit claim was overstated

The original: *"you know B3's score on the misleading-symptom subset."*
At that point Tier-1 is sealed and Tier-2 does not exist, so it is
Tier-3 only. Corrected wording is in §6.3.

✓ Worth noting this is the doc's own warning turned on itself — §9
warns about "the number that means nothing" and then §13's exit
criterion reports exactly that number without the qualifier.

## C5 — the Tier-1 seal, and what it does to the schedule 🔴

The Day-2 thread raised the leak (its GT-1) and is right. What it did
not carry through is the consequence:

```text
IF the test split is sealed until Phase 4,
THEN Phase 4 is the FIRST real-data signal in
     the entire project.

Finding out at the last gate that it does not
work is the C3 problem again, worse.
```

Resolution: sealed, **plus** a dev-split checkpoint at Gate 2. The two
runs stop being the same experiment done twice — one is formative and
you may iterate against it, the other is summative and runs once.

## C6 — two new Layer 2 schema fields, before authoring

`applies_to` and signal-conditional `remediation[]`. Both from the XID
catalog; neither in the original design, because the chat read those
docs at much lighter depth than the catalog rewards. Detail and example
in §6.1.

✓ Also: adopt NVIDIA's own remediation vocabulary — their Resolution
Bucket columns, Immediate and Investigatory — rather than inventing
one. Free interoperability, and it is citable.

## C7 — the working mechanism, made explicit 🔴

§1. Your rule existed; its enforcement did not.

## C8 — new Phase 0

Four small things that are cheap now and annoying later.

## C9 — the minimum cut, agreed up front

§14.

---

# Appendix B — quick reference

```text
PROJECT      Gforensics
REPO         github.com/SARPAT/Gforensics
LICENSE      Apache-2.0
LANGUAGE     Python
CLI          gforensics diagnose GPU-042

ANCHOR       root-cause attribution
             hardware vs software, which
             component, with evidence

AUDIENCE     mid-tier GPU operators
             100–2k GPUs, no reliability team

CORE ASSET   causal-kb/ — versioned YAML,
             contradicting signals, cited
             sources

KEY PROPERTY LLM chooses the PATH
             deterministic layer produces
             the VERDICT

KEY SCHEMA   three-state events
             MEASURED_PRESENT
             MEASURED_ABSENT
             NOT_MEASURED

KEY METRIC   accuracy on the misleading-
             symptom subset vs baselines

KEY GUARD    simulator ⊥ diagnoser,
             enforced in CI

NEVER        write to the fleet.
             Recommend only.
```

```text
SOURCE DOCUMENTS

/mnt/project-files/
  GFORENSICS_SOURCE_CHAT.md       11,014 lines
    THE record of what was decided. Where it
    disagrees with the context doc, it wins.
  GFORENSICS_PROJECT_CONTEXT.md    1,646 lines
    the distillation. Lossy in places.
  XID_Errors.pdf     NVIDIA Release 615, 78pp
  meta_paper.pdf     Kokolis et al., HPCA 2025
  minder_paper.pdf   Deng et al., 2411.01791
```

```text
NEXT ACTION

Four answers: Q1, Q2, Q3, Q4.
Then Phase 0 starts, and the first thing
I hand you is the design note for 0.1.
```
