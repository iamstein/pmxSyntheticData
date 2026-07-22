# Review backlog

Prioritized findings from a code review on 2026-07-22, covering `R/`,
`design/`, `tests/`, and the vignettes at commit `bf1ebd2` plus the
uncommitted working tree.

This is a living backlog in the same spirit as `design/TEST_SIM.md`. `TEST_SIM.md`
tracks *simulation* defects found by evaluating output; this file tracks
*mechanism, privacy-accounting, and API* defects found by reading the code.
When an item here produces a reproducible output failure, mirror it into the
`TEST_SIM.md` issue registry with a gate and close it here.

Status values: `open`, `in-progress`, `closed`, `wontfix`.

---

## Part 1 — Why epsilon has to be so large right now

This section exists because the headline symptom ("utility only appears at
epsilon 50-500") has *two* independent causes that look identical in a plot.
Separating them changes what you should fix first.

### The noise arithmetic

Every source-dependent number this package releases is a **column sum over
subjects**, computed from a per-subject row clipped to `[0, 1]`. The Laplace
mechanism adds noise with scale

```
b = sensitivity / epsilon_group
```

`sensitivity` is the L1 sensitivity: the largest total change one subject can
cause across the whole released vector. `.release_matrix_sum()`
(`R/representation.R:496`) charges `sensitivity = ncol(matrix)` — the worst case
where a single subject moves every coordinate by the full 1.0.

Measured on `pmx_simulated_fixture(60)` at `epsilon = 5` with the default
budget split, using the real OpenDP backend:

| query | epsilon | sensitivity | dims | Laplace scale `b` |
|---|---:|---:|---:|---:|
| `subject_count` | 0.50 | 1 | 1 | 2 |
| `event_and_regimen` | 0.75 | 9 | 9 | 12 |
| `endpoint_timing` | 0.75 | 36 | 36 | 48 |
| `endpoint_trajectories` | 2.00 | 40 | 40 | 20 |
| `baseline_covariates` | 0.50 | 8 | 8 | 16 |
| `censoring` | 0.50 | 12 | 12 | 24 |

So the noise added to each trajectory coordinate has scale 20, while the true
value of that coordinate is a count bounded by N = 60. That is signal-to-noise
below 1 on essentially the entire release.

### The part that is not actually a problem: N

Almost everything decoded from these sums is a **ratio** — a mean or a
probability — of the form `released_sum / released_count`. The noise on that
ratio is approximately

```
error on a decoded unit-scale mean  ~=  b / N  =  sensitivity / (epsilon_group * N)
```

The `N` in the denominator is the whole story. For the trajectory group above
(`b = 20`):

| N | approx. error on a `[0,1]` unit-scale mean |
|---:|---:|
| 60 | 0.33 — unusable, the domain is only 1.0 wide |
| 200 | 0.10 |
| 600 | 0.033 |
| 2000 | 0.010 — good |

This is confirmed empirically. At N = 2000 and `epsilon = 5`, the released
per-cell presence counts came back as 1988.7, 1997.5, 2058.9, 1994.5 against a
true value of 2000 — accurate to well under 1%.

**Conclusion: the mechanism is already fine at realistic clinical N.** The
demos and fixtures are 8-60 subjects, which is the regime where *any* honest DP
mechanism fails. A pooled dataset of several hundred subjects at `epsilon = 5`
is already in usable territory with today's code. What is missing is not
primarily a better mechanism — it is telling the user, before they spend
budget, whether their (N, epsilon, dimension) combination can work at all. See
`REV-002`.

### The part that *is* a bug, and hurts at every N

Separately from noise magnitude, the decode layer compares **raw noisy counts**
against the literal constant `0.25`, as if they were probabilities in `[0, 1]`.
They are not — they are unnormalized sums of order N.

`.decode_trajectories()` (`R/representation.R:624`):

```r
value_unit <- ifelse(presence > 0.25, value_sum / pmax(presence, 1e-8), NA_real_)
```

`presence > 0.25` is meant to ask "did this grid cell have any released
support?". At N = 2000 with `b = 20`, a cell with *zero* real support routinely
draws noise of +43 and sails through the gate. Its `value_sum` is separately
noised, clamped at 0 by `pmax(..., 0)`, so the cell decodes to `0 / 43 = 0`,
which `.from_unit()` maps to the **bottom of the working domain**.

Observed directly at N = 2000, `epsilon = 5`, log-transformed `cp` endpoint
(working scale spans about -8.5 to 5.3):

```
true  presence : 2000 2000 2000    0 2000    0    0    0   0   0
noisy presence : 1989 1998 2059    0 1995 43.3 10.7    0 0.7 0.7
true  curve    : 0.088 2.11 1.41 1.03 0.434 0.434 0.434 0.434 0.434 0.434
noisy curve    : 0.14  2.43 1.06 0.873 0.584 -2.09 -8.52 -8.52 -8.52 -8.52
```

The first five cells — the ones with real support — are *accurate*: errors of
0.2-0.35 on a domain 13.8 wide, exactly the `b/N` prediction. The last five are
pinned to the domain floor. That is not noise; that is a broken gate. And
because `.fill_unoccupied_curve()` only interpolates cells that fail the same
threshold, it cannot rescue them — the bad cells are labelled "occupied".

So a meaningful share of the visual damage in the epsilon vignette is a
scale-inconsistency defect, not an inherent privacy cost. Fix `REV-001` before
concluding anything about how much epsilon this design needs.

---

## Part 2 — Prioritized issues

### P0 — Fix before drawing further conclusions about privacy/utility

| ID | Area | Issue | Suggested direction | Status |
|---|---|---|---|---|
| `REV-001` | Decoding | Raw noisy counts compared against the literal `0.25` as if they were probabilities. Occurs at `R/representation.R:592, 605, 624, 640, 656, 658, 685`. Note the inconsistency *within* `.decode_timing()`: line 581 correctly divides by `count` first, line 592 does not. Unoccupied cells decode to a domain endpoint instead of "no support", at every N. | Gate on a scale-aware threshold, e.g. `max(f * private_count, k * b)`. The noise scale `b = sensitivity / epsilon` is already recorded in the accounting table, so a principled threshold is available for free — pass it into the decoders. Add a regression test asserting that a grid cell with zero true support never decodes to a working-domain endpoint. | open |
| `REV-002` | API / guidance | Nothing warns a user that their N is too small for their epsilon and release dimension until after the budget is irreversibly spent. The existing check (`R/fit.R:252`) fires on `dimensions > 6 * count`, which is dimension-vs-N only and ignores epsilon entirely. | Add a public pre-flight helper that takes the configuration (no data) and reports the predicted `sensitivity / (epsilon_group * N)` error per release group against a stated usability threshold. Document the `N >~ sensitivity / (epsilon_group * target_error)` envelope in the epsilon vignette. This converts "unusable" into "usable within a stated envelope", which is the honest and far more useful claim. | open |

### P1 — Privacy correctness

| ID | Area | Issue | Suggested direction | Status |
|---|---|---|---|---|
| `REV-003` | DP guarantee | Data-dependent `stop()` on confidential rows *before* any noise is applied: `validate_pmx(..., strict = TRUE)` at `R/fit.R:206`, plus `R/representation.R:90` ("An observed DVID is not covered...") and `R/representation.R:215` ("A subject-property value is outside the declared public category levels"). Whether the call throws — and its message — is a function of one individual's record. This is an unaccounted output channel in exactly the place the package claims formal DP. | Drop or clip out-of-domain records rather than erroring, matching how numeric bounds are already handled by `.clip()`. If a hard failure must be retained, route it through a private test and account for it. Either way, disclose it in `proof_assumptions` (`R/fit.R:271`) and `design/PRIVACY_ARGUMENT.md`. | open |
| `REV-004` | Accounting | `delta` is validated and requires a written justification when positive (`R/fit.R:14-24`), but every mechanism is Laplace and every accounting entry hardcodes `delta = 0` (`R/privacy.R:158`). `unspent_delta` always equals the request. Users are asked to justify a parameter that is never spent. | Either restrict the API to `delta = 0` and say so, or wire delta to a real approximate-DP mechanism — which is the same work as `REV-006`. Do not leave it as decorative. | open |

### P2 — Utility headroom (real work, do after P0/P1)

| ID | Area | Issue | Suggested direction | Status |
|---|---|---|---|---|
| `REV-005` | Sensitivity | `sensitivity = ncol(matrix)` is sound but pessimistic. A subject occupies a handful of trajectory/timing cells, not all of them; the true row L1 is bounded by `2 * min(cells, observation_limit)` per endpoint, and the timing matrix's true bound is `n_cells + 2 * max_occasions` rather than `ncol`. | Derive the bound from the contribution limits already declared in `pmx_contribution_limits()` rather than from matrix width. Cheap, no change to the proof structure, and it makes `max_timing_cells` do real work — today it only caps grid size (`R/endpoints.R:157, 182`) and never enters a sensitivity argument. | open |
| `REV-006` | Mechanism | Pure-DP Laplace with basic sequential composition costs linearly in dimension. Gaussian noise under zCDP/RDP accounting costs roughly `sqrt(d)` instead of `d`, and composes better across the six query groups. Rough estimate for the trajectory group at epsilon 5: Laplace sd ~28 vs Gaussian sd ~12 under zCDP. | Add a zCDP accountant alongside the existing basic-composition one, and a Gaussian measurement in the OpenDP adapter. This is the natural consumer of `delta` (`REV-004`). Keep the pure-DP path as the default and make the approximate-DP path opt-in. | open |
| `REV-007` | Representation | The trajectory group spends 40 numbers on per-cell presence/value pairs to describe what is qualitatively a 3-4 parameter curve. Dimension is the dominant cost term under any accountant. | Investigate releasing a low-dimensional shape (spline/basis coefficients, or a small set of quantiles) instead of a dense grid. Highest ceiling of anything on this list, and the most work. | open |
| `REV-008` | Post-processing | The decoders carry a lot of unlabelled rescue logic: `.ensure_grid_presence()` forces at least 3 cells regardless of the release (`R/generate.R:119`), variance floors `0.05^2`/`0.01^2`/`0.25` (`R/representation.R:658-660`), the `0.95` rate cap (`:686`). All are privacy-safe post-processing, but collectively they mean that at high noise the generator is mostly sampling from hardcoded priors — which undercuts "source-calibrated". | Promote these to named, documented constants. Add a diagnostic reporting what fraction of the output shape is attributable to the release versus to the fallbacks, so the honest claim is measurable rather than asserted. | open |

### P3 — Integrity and hygiene

| ID | Area | Issue | Suggested direction | Status |
|---|---|---|---|---|
| `REV-009` | Governance | `.public_input_manifest()` (`R/fit.R:103-124`) accepts six arguments, uses none of them, and returns a hardcoded 8-row constant that ships into the release ledger as `public_inputs`. It is formatted like an audit record and contains no information about the fit it documents. | Derive it from the actual inputs, or delete it. In a governance context a convincing-looking empty artifact is worse than no artifact. | open |
| `REV-010` | Leakage guard | The prohibited-payload check (`R/privacy.R:247-252`) is a nine-name denylist. It would not catch `subjects`, `piece`, or `rows`. | Invert to an allowlist over the expected released structure. A denylist is a smoke detector, not a guard, and it is currently presented as the latter. | open |
| `REV-011` | API | No `print.pmx_private_validation` or `print.pmx_backend_tests` method exists, so both exported classed returns dump as raw lists. Compare the five `print` methods that are registered in `NAMESPACE`. | Add both methods. | open |
| `REV-012` | Testing | `run_dp_backend_tests()` advertises a `"privacy_map"` entry in its `tests` vector (`R/privacy.R:135`) but `passed` only checks lengths and finiteness. The map check happens incidentally inside `release()`. | Either assert the privacy relation explicitly or stop naming a test that is not run. | open |
| `REV-013` | Side effects | `.opendp_backend()` calls `enable_features("contrib")` on every resolve (`R/privacy.R:5`), mutating global OpenDP state as a side effect of ordinary package use. | Do it once, guarded, and document it. | open |
| `REV-014` | Process | 8 commits total against a ~1,200-line uncommitted working tree that contains a whole feature (`R/properties.R`, the evaluation harness, `pmxSynthData-epsilon-exploration.Rmd`). Large unreviewed surface for a package making formal privacy claims. | Land the working tree in reviewable commits before starting on this backlog. | open |
| `REV-015` | Docs | ~2,100 lines of vignette against ~3,500 lines of R, with `AGENTS.md` imposing a manual synchronization burden on every change. | Convert load-bearing prose claims into assertions or regression tests, per `AGENTS.md`'s own guidance, so they cannot silently go stale. | open |

---

## Suggested order of work

1. `REV-014` — land the working tree so the rest is reviewable.
2. `REV-001` — the decode threshold bug. Cheap, and it changes what the
   epsilon vignette shows, so everything downstream depends on it.
3. `REV-003` — the data-dependent `stop()` paths. Cheap, and it is a
   correctness issue in the package's central claim.
4. Re-run `scripts/evaluate_simulations.R` and the epsilon sweep. **Re-measure
   before planning further.** The remaining utility gap may be much smaller
   than it looks today.
5. `REV-002` + `REV-005` — planning helper and tighter sensitivity. Together
   these likely make `epsilon = 5` defensible at realistic N without touching
   the mechanism.
6. `REV-004` + `REV-006` — Gaussian/zCDP, if step 4 shows it is still needed.
7. `REV-007` — representation redesign, only if steps 5-6 are insufficient.
8. P3 items opportunistically.

## Caveats on this review

- The `b/N` convergence claim and the `REV-001` diagnosis were verified
  empirically against `pmx_simulated_fixture()` at N = 60, 600, and 2000. The
  *proposed fix* for `REV-001` was not implemented or tested.
- The Gaussian/zCDP noise estimate in `REV-006` is an order-of-magnitude
  calculation, not a derived bound. Derive it properly before committing to it.
- Sensitivity bounds in the current code were checked for soundness and appear
  correct everywhere reviewed. `REV-005` is about tightness, not correctness.
