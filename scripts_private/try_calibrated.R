# Try the calibrated generator on a real modeling dataset.
#
# Run inside the safe computing environment. This is the ONLY script in the
# package that is meant to touch confidential data, and it lives in a folder
# that is gitignored so nothing here can be committed. Read README.md first.
#
# Workflow, following design/MODEL_ELICITATION.md and design/DATA_ELICITATION.md:
#   1. fill in the CONFIG block from your protocol and preclinical predictions
#   2. run once with USE_FIXTURE = TRUE to prove the plumbing on public data
#   3. set USE_FIXTURE = FALSE and point DATA_PATH at the real dataset
#   4. inspect the pre-flight, then the fit, then the generated table
#
# Nothing about the real data leaves this environment except, if you choose to
# export it, the fitted model and the generated mock table -- and even those
# require governance sign-off. The source-vs-mock comparison is a restricted
# diagnostic; keep it here.

library(pmxSynthData)

# If the package is not installed in this environment, load it from source:
# devtools::load_all("/path/to/pmxSyntheticData")

# ============================================================================
# CONFIG  --  everything you must fill in is in this block
# ============================================================================

USE_FIXTURE <- TRUE          # TRUE: dry run on public simulated data.
                             # FALSE: use the real dataset at DATA_PATH.

DATA_PATH <- "data/your_modeling_dataset.csv"   # relative to this folder
OUT_DIR   <- "output"

EPSILON <- 0.5               # from governance, NOT chosen to look good

# --- Column roles: map YOUR column names onto PMX roles ---------------------
# Only the roles your dataset actually has. Unused roles stay NULL.
ROLES <- pmx_roles(
  id       = "ID",
  time     = "TIME",
  dv       = "DV",
  amt      = "AMT",
  evid     = "EVID",
  dvid     = "DVID",          # set NULL if you have a single endpoint
  cmt      = "CMT",
  mdv      = "MDV",
  occasion = NULL,
  cens     = NULL,
  exclude  = NULL             # columns to drop before fitting
)

# Which DVID value marks the PK endpoint (concentration). The calibrator looks
# for endpoint "cp"; map your coding to it below in PREP if it differs.
PK_DVID <- "cp"
PD_DVID <- NA                 # set to your PD DVID to calibrate a PD level too

# --- Public structural model (design/MODEL_ELICITATION.md) ------------------
# From preclinical scaling / the FIH prediction memo. NOT from this dataset.
MODEL <- pmx_structural_model(
  pk      = "1cmt_oral",                      # or 1cmt_iv/infusion, 2cmt_*
  typical = c(cl = 10, v = 70, ka = 1),       # predicted typical values
  pd      = "none",                           # or constant/linear/exponential
  source  = "FILL IN: e.g. allometric scaling memo v3",
  iiv     = c(cl = 0.3, v = 0.2),
  residual_cv = 0.15
)

# --- Public trial design (design/DATA_ELICITATION.md) -----------------------
# From the protocol. Sampling times are the nominal schedule, not observed times.
DESIGN <- pmx_trial_design(
  dose_levels  = c(10, 30, 100),
  cohort_sizes = c(1, 1, 1),                  # relative; used to weight arms
  sampling     = c(0, 0.5, 1, 2, 4, 8, 12, 24),
  n_doses      = 1,
  dose_interval = 24,
  duration     = 0,                           # infusion length, 0 = bolus/oral
  source       = "FILL IN: protocol vX section Y"
)

# --- Public priors on the correction factors --------------------------------
# The prior on how wrong the PREDICTION is, not on the parameter. See
# design/PROTOTYPE_SPEC.md section 6. Provenance is mandatory.
PRIORS <- pmx_priors(
  pk = pmx_prior(c(1 / 4, 4), source = "FILL IN: allometric scaling accuracy")
  # pd = pmx_prior(c(1 / 4, 4), source = "FILL IN")   # if PD_DVID is set
)

# --- Optional per-dataset preparation ---------------------------------------
# Recode DVID to the "cp"/"pd" the calibrator expects, drop screening rows, fix
# units, etc. Receives the raw data frame, returns a cleaned one.
PREP <- function(d) {
  # Example: map a numeric DVID to endpoint labels
  # d$DVID <- ifelse(d$DVID == 1, "cp", ifelse(d$DVID == 2, "pd", NA))
  d
}

# ============================================================================
# WORKFLOW  --  you should not need to edit below here
# ============================================================================

dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

read_data <- function() {
  if (USE_FIXTURE) {
    message("USE_FIXTURE = TRUE: generating public simulated data, not reading ",
            "your dataset.")
    # A stand-in with the same schema pmx_generate() produces, so the plumbing
    # is exercised end to end before any real data is touched.
    truth <- pmx_structural_model("1cmt_oral", c(cl = 22, v = 70, ka = 1),
                                  source = "fixture truth (2.2x the prediction)")
    return(pmx_generate(truth, DESIGN, n_subjects = 40, seed = 1))
  }
  if (!file.exists(DATA_PATH)) {
    stop("DATA_PATH does not exist: ", normalizePath(DATA_PATH, mustWork = FALSE))
  }
  utils::read.csv(DATA_PATH, stringsAsFactors = FALSE)
}

raw <- PREP(read_data())
roles <- if (USE_FIXTURE) pmx_generated_roles() else ROLES

message("\n== Source structural validation (restricted) ==")
report <- validate_pmx(raw, roles, strict = FALSE)
print(report$valid)
if (!report$valid) {
  print(report$checks[report$checks$status == "error", c("check", "message")])
  stop("Source data failed structural validation; fix the mapping first.")
}

n_subjects <- length(unique(raw[[roles$id]]))
message("\n== Pre-flight (no data read, no budget spent) ==")
print(pmx_preflight(PRIORS, epsilon = EPSILON, n_subjects = n_subjects))

# --- The only budget-spending step ------------------------------------------
message("\n== Calibrated fit ==")
backend <- if (USE_FIXTURE) "public" else "opendp"
fit <- fit_calibrated_pmx(
  raw, roles, MODEL, DESIGN, PRIORS,
  epsilon = EPSILON,
  backend = backend,
  public_source = USE_FIXTURE          # NEVER TRUE for real confidential data
)
print(fit)

message("\n== Provenance (goes in the release record) ==")
print(fit$provenance)

# --- Generation is post-processing; costs no further budget -----------------
message("\n== Generate mock data ==")
mock <- pmx_generate(fit, seed = 1234)
message("Generated ", nrow(mock), " rows for ",
        length(unique(mock$ID)), " subjects.")
stopifnot(validate_pmx(mock, pmx_generated_roles())$valid)

# The mock table is safe to export once governance approves. Write it here so it
# stays in the gitignored output folder.
utils::write.csv(mock, file.path(OUT_DIR, "mock.csv"), row.names = FALSE)
saveRDS(fit, file.path(OUT_DIR, "calibrated_model.rds"))

# --- RESTRICTED diagnostic: source vs mock ----------------------------------
# This is source-derived. It must stay in the safe environment; do not export
# these figures. It is here only so you can judge whether the mock data is
# "vaguely right" before deciding to release it.
message("\n== Restricted source-vs-mock diagnostic ==")
if (requireNamespace("ggplot2", quietly = TRUE)) {
  obs <- function(d, r, label) {
    keep <- d[[r$evid]] == 0 & !is.na(d[[r$dv]])
    data.frame(dataset = label,
               time = as.numeric(d[[r$time]][keep]),
               dv = as.numeric(d[[r$dv]][keep]))
  }
  compare <- rbind(obs(raw, roles, "source"),
                   obs(mock, pmx_generated_roles(), "mock"))
  p <- ggplot2::ggplot(compare,
                       ggplot2::aes(time, dv, colour = dataset)) +
    ggplot2::geom_point(alpha = 0.4, size = 0.7) +
    ggplot2::facet_wrap(~dataset, ncol = 1) +
    ggplot2::labs(title = "RESTRICTED: source vs synthetic (do not export)",
                  x = "Time", y = "DV") +
    ggplot2::theme_minimal()
  ggplot2::ggsave(file.path(OUT_DIR, "RESTRICTED_source_vs_mock.png"), p,
                  width = 7, height = 6, dpi = 110)
  message("Wrote ", file.path(OUT_DIR, "RESTRICTED_source_vs_mock.png"),
          " (restricted; keep in the safe environment)")
} else {
  message("ggplot2 not available; skipping the diagnostic plot.")
}

message("\nDone. Review the pre-flight verdict and the fit's correction ",
        "factors before treating any output as usable.")
