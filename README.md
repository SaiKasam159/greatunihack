# Finance Your Friday
**GreatUniHack 2026 · NatWest Challenge: AI-Powered Financial Inclusion & Resilience**

> Money apps fail at the moment people need them most: the moment before a bad spend, and the morning after one. We built for both.

---

## 1. The problem

- People overspend at predictable moments: Friday nights, just after payday, after a stressful week, when friends are out. Current apps only tell you about it afterwards.
- After a bad night, people avoid opening their banking app. Behavioural economists call this the **ostrich effect**: we avoid financial information when we expect bad news. Avoidance is where the real damage happens, because problems compound when nobody's looking.
- People in financial difficulty are usually told to "budget better". What actually moves them out of crisis is a structured path: **an emergency buffer first, then savings, then long-term growth**.

## 2. The solution

An AI financial coach that:

1. **Predicts when you're most vulnerable to overspending** from your own transaction history and context, and steps in *before* it happens.
2. **Builds you a personalised financial plan** using a team of specialist AI agents, split across multiple funds (emergency, savings, growth).
3. **Turns the plan into weekly checkpoints**, with a Saturday-morning check-in designed so that opening the app after a bad night feels like recovery, not judgement.
4. **Shows you your financial future** ("financial time travel"): Monte Carlo projections of each fund, and how vulnerable-moment spending changes them.

---

## 3. Core engine: vulnerability prediction

This is our key differentiator. The question we answer isn't "how much do you spend?" but **"when are you most likely to spend more than you meant to?"**

### Inputs (features)
| Feature | Why it matters |
|---|---|
| Day of week × hour of day | Captures the Friday-night effect |
| Days since payday | Spending spikes right after money lands |
| Current balance relative to usual | "Feeling rich" vs "running low" behaviour |
| Spend in the last 3 / 24 hours | Momentum: one drink becomes five |
| Merchant category mix (bars, takeaways, gambling, online shopping) | Different triggers for different people |
| Recent unusual transactions | Stress or life events |
| Calendar/events (optional, synthetic for demo) | Birthdays, matches, nights out |

### Model
- Split history into hourly windows. **Label:** did spending in the next window exceed the user's personal threshold (e.g. their 90th percentile)?
- **Gradient-boosted classifier** (LightGBM / sklearn) outputs a **vulnerability score** for each upcoming window.
- **SHAP explanations** for each prediction, so the coach can say *why*: "Friday + 2 days after payday + £40 already spent tonight." This covers the brief's **transparent and ethical AI** criterion.

### Output
- A weekly "vulnerability map" (a heatmap of risky windows).
- Real-time nudges when the score passes a threshold.

---

## 4. Multi-agent planning system

**The agents lead decides the agent architecture.** The rest of the team only needs the agents to meet this interface:

- **Inputs:** user goals, transaction history, vulnerability model outputs, Monte Carlo engine (as callable tools).
- **Outputs (structured JSON):** a plan split across the emergency / savings / growth funds, weekly checkpoints, and coach messages for the Friday nudge and Saturday check-in.
- **Must enforce:** the fund ladder rules (section 5) and the ethics rules (section 9).
- **Flow:** user states goals → agents build the plan → user reviews → plan becomes checkpoints.

---

## 5. The fund ladder

Investment goals are central, but in a responsible order:

1. **Emergency fund** (easy-access savings): target of 1–3 months of essential costs. Always first.
2. **Savings fund**: short- and medium-term goals (deposit, course, car).
3. **Growth fund** (e.g. stocks & shares ISA / index fund): **unlocks once the emergency fund hits its target**, enforced by the agents.

**Monte Carlo projections** for each fund:
- Emergency/savings: contributions plus a savings rate, with income and expense shocks simulated.
- Growth: contributions plus stochastic returns (illustrative mean and volatility), giving a fan chart.
- Two scenarios side by side: **"recovered"** (sticks to plan) vs **"repeated vulnerable Fridays"**. This shows the compounding cost of overspending.
- Headline resilience metric: *"Probability you can cover a surprise £300 bill next month."*

---

## 6. The weekly loop

### Friday, before the risk window (prevention)
- Push nudge timed by the vulnerability model: *"Friday evenings after payday are usually your biggest spend. Want to set a night-out budget?"*
- User sets their own budget, so the next morning's review compares against **their** number, not ours.
- Shows the snowball: what repeated overspending does to their growth fund over 5 years.

### Saturday morning (recovery)
- One number, one fix, one chart: *"Friday was £85 over your budget. Skip two takeaways this week and you're back on track."* The forecast line visibly bends back to target.
- Never opens with the raw damage. Leads with the way back.

---

## 7. Checkpoints

**We keep checkpoints, and drop levels/XP.** Checkpoints are what connects the plan to real behaviour. Without them, the plan is a PDF nobody reads.

- The agents break the plan into **weekly checkpoints** (e.g. "Emergency fund: £120 → £150", "Takeaways under £30").
- **The Saturday check-in *is* the weekly checkpoint.** One ritual, not two.
- A missed checkpoint triggers a re-plan from the agents, not a failure message.

## 8. Rewarding the Saturday check-in

The reward has to make opening the app after a bad night feel *good*:

1. **Instant: "repair your forecast".** Checking in unlocks a one-tap recovery move (e.g. sweep £15 into the emergency pot, or trim next week's takeaway budget). The user sees their future recover in real time. That's the reward: control, not a badge.
2. **Ongoing: the check-in streak counts showing up, not being perfect.** Checking in after a bad night still extends the streak. A streak of consecutive check-ins unlocks a **boosted interest rate on the emergency fund**. That's a real, bank-deliverable reward, and it gives NatWest a reason to ship it.

---

## 9. Ethics and inclusion

- **Explainable:** every nudge says why (SHAP reasons), no black-box judgements.
- **No shame by design:** recovery-first messaging, streaks reward honesty, user-set budgets.
- **The agents enforce** affordability and the fund ladder, so no risky investing for people without a buffer.
- **Guidance, not regulated advice:** the app suggests fund *types* and allocations, not specific products.
- **Accessibility:** plain-language explanations, a choice of coach tone, safe-to-spend-until-payday shown instead of a raw balance.
- **Data:** synthetic data for the demo; in production, UK Open Banking consent flows.

## 10. Fit to the judging criteria

| Criterion | How we hit it |
|---|---|
| Customer focus | Designed around the morning after and the ostrich effect, a real behaviour |
| Innovation | Predicting *vulnerable moments*, not just spend totals |
| Social impact | Fund ladder moves people from crisis to resilience to growth; affordability checks protect vulnerable users |
| AI & data | Vulnerability classifier + SHAP, Monte Carlo "financial time travel", genuine multi-agent planning |
| Feasibility | Open Banking data, boosted-rate reward deliverable by a bank, simple stack |

---

## 11. Demo script (3–4 minutes)

Persona: **Maya, 24**, retail worker, paid monthly, no savings buffer, Friday nights out.

1. **Onboarding (30s):** Maya tells the coach her goal ("stop being broke by the 20th, start investing"). The agents build her plan across the three funds, holding back growth until the emergency fund exists.
2. **Vulnerability map (45s):** heatmap shows Friday 8pm–1am after payday as her red zone, with SHAP reasons.
3. **Friday 6pm nudge (45s):** alert fires; Maya sets a £40 budget; the snowball chart shows the 5-year cost of repeated overspending.
4. **Saturday morning (60s):** she overspent. The check-in shows one number, one fix, a one-tap sweep, the forecast recovering, and her streak extending.
5. **Close (30s):** fund projections, resilience probability, pitch line.

---

## 12. Build plan (team of 4, 4 hours)

### Roles
| Person | Owns |
|---|---|
| **1 – ML** | Synthetic transaction generator (with Friday/payday patterns), vulnerability classifier, SHAP explanations |
| **2 – Agents** | Agent architecture (their call); shared tool layer; structured JSON outputs matching section 4 |
| **3 – Frontend** | Streamlit app: onboarding/plan, vulnerability heatmap, Friday nudge, Saturday check-in, fund projections |
| **4 – Simulation + pitch** | Monte Carlo engine for the three funds, slides, demo script, backup video, integration testing |

### Timeline
| Time | Milestone |
|---|---|
| 0:00–0:20 | Lock scope; agree data schema (`timestamp, amount, category, merchant, balance`) and agent JSON formats |
| 0:20–2:30 | Parallel build; frontend uses mock data until real outputs are ready |
| 2:30–3:15 | Integration: model → agents → UI |
| **3:15** | **Feature freeze** |
| 3:15–3:50 | Rehearse demo twice, record backup video |
| 3:50–4:00 | Buffer |

### Stack
Python · pandas · LightGBM/scikit-learn · SHAP · NumPy (Monte Carlo) · LLM API with tool calling · Streamlit

### Cut list (dropped)
- Voice decoder
- Levels, XP and wider gamification
- Real bank integration (synthetic data only)

---

## 13. Pitch lines
- *"Money apps fail at the moment people need them most: the morning after. We built for that moment."*
- *"We don't predict how much you spend. We predict when you're vulnerable."*
- *"Emergency first, then savings, then growth. A ladder out of crisis, not a lecture."*
