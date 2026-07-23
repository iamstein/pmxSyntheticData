# AVATAR synthesis on your own modeling dataset -- a starting template.
#
# AVATAR blending is the DEFAULT synpmx method. Use it when the synthetic data
# STAYS INSIDE your trusted computing environment (you are the only consumer;
# governance and access controls apply). It resamples and blends whole source
# subject trajectories -- faithful, and far less ceremony than the differentially
# private path -- but makes NO formal privacy guarantee. If the data may cross a
# trust boundary, use try_dp_calibrated.R instead. See the "synpmx-privacy"
# vignette for the decision rule (which method when).
#
# Run this in the safe computing environment. Nothing here leaves it: the
# synthetic table and the source-vs-synthetic figure are both source-derived.
#
# To use: edit the two CONFIG blocks -- the data path and the column roles --
# and run. You should not need to touch anything below them.

library(synpmx)
# If synpmx is not installed here: devtools::load_all("/path/to/synpmx")

# ============================================================================
# CONFIG 1 -- where the data is
# ============================================================================

DATA_PATH  <- "data/your_modeling_dataset.csv"
OUT_DIR    <- "output"
SEED       <- 1234        # reproducibility seed; the caller's RNG is untouched
N_SUBJECTS <- NULL        # NULL keeps the source cohort size

# Optional cleanup before synthesis: filter to one study, fix units, recode a
# column. Receives the raw data frame, returns a cleaned one. Pooling two assays
# with different limits will trip the censoring check, so filter to one study
# here if that applies.
PREP <- function(d) {
  d
}

# ============================================================================
# CONFIG 2 -- what the columns mean
# ============================================================================
# Declare only the roles your dataset has. Every column NOT named by a role is
# dropped -- the run prints which -- so a stray identifier cannot leak out of a
# real subject by being forgotten.

ROLES <- pmx_roles(
  id       = "ID",
  time     = "TIME",
  dv       = "DV",
  amt      = "AMT",
  evid     = "EVID",
  dvid     = "DVID",   # one endpoint-key column, or several that agree:
                       #   dvid = c("YTYPE", "NAME") declares a numeric key and
                       #   a character label; both are checked and carried out.
  cmt      = "CMT",
  mdv      = "MDV",
  rate     = NULL,     # infusion RATE column, if any
  occasion = NULL,     # occasion column, if TIME resets by occasion
  cens     = NULL,     # below-limit indicator (Monolix: 1 below, -1 above), if
  limit    = NULL,     #   the study has BLQ data; limit is the interval's far end

  # BLENDED into genuinely new values across neighbours -- use for baselines you
  # want synthesized (weight, age). Do NOT list a baseline that is itself an
  # endpoint's starting value (e.g. baseline B cells beside a B-cell endpoint):
  # covariates and endpoints are blended independently, so the two would not
  # agree (REV-022).
  covariates = c("WT", "AGE", "SEX"),

  # COPIED verbatim from the subject that supplied the doses, so it stays
  # coherent with them -- treatment arm, dose group, study id, a character
  # endpoint label. A kept value is one real subject's real value.
  keep     = NULL
)

# ============================================================================
# WORKFLOW -- you should not need to edit below here
# ============================================================================

dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

raw <- PREP(utils::read.csv(DATA_PATH, stringsAsFactors = FALSE))
roles <- ROLES

message("\n== Source structural validation ==")
report <- validate_pmx(raw, roles, strict = FALSE)
if (!report$valid) {
  print(report)   # names each problem, the role, and the column it maps to
  stop("Source failed structural validation. See the numbered problems above; ",
       "each says which role and column to fix in `pmx_roles()`.", call. = FALSE)
}
message("  valid; ", length(unique(raw[[roles$id]])), " subjects")

message("\n== AVATAR synthesis ==")
synthetic <- synpmx_avatar(raw, roles, n_subjects = N_SUBJECTS, seed = SEED)
stopifnot(validate_pmx(synthetic, roles)$valid)
message("  generated ", nrow(synthetic), " rows for ",
        length(unique(synthetic[[roles$id]])), " subjects; new identifiers: ",
        length(intersect(synthetic[[roles$id]], raw[[roles$id]])) == 0)

utils::write.csv(synthetic, file.path(OUT_DIR, "avatar_synthetic.csv"),
                 row.names = FALSE)

# --- Restricted diagnostic: source vs synthetic -----------------------------
# Source-derived. Keep it in the safe environment; do not export the figure.
message("\n== Restricted source-vs-synthetic diagnostic ==")
if (requireNamespace("ggplot2", quietly = TRUE)) {
  # The plot adapts to however many endpoints there are -- one PK, one PD, two,
  # more -- because faceting by endpoint grows a column per endpoint on its own.
  # You do not have to know the count in advance.
  #
  # Facet strips read best from a character label. If you declared several `dvid`
  # columns, the last one (often a character NAME) is used; otherwise the single
  # dvid column; otherwise a constant.
  label_col <- if (length(roles$dvid) > 1L) {
    roles$dvid[[length(roles$dvid)]]
  } else if (!is.null(roles$dvid)) roles$dvid[[1L]] else NULL

  frame <- function(d, label) {
    keep <- d[[roles$evid]] == 0 & !is.na(d[[roles$dv]])   # observations only
    data.frame(
      dataset  = label,
      id       = d[[roles$id]][keep],
      time     = as.numeric(d[[roles$time]][keep]),
      dv       = as.numeric(d[[roles$dv]][keep]),
      endpoint = if (is.null(label_col)) "DV" else
        as.character(d[[label_col]][keep]),
      stringsAsFactors = FALSE
    )
  }
  compare <- rbind(frame(raw, "source"), frame(synthetic, "synthetic"))

  p <- ggplot2::ggplot(compare, ggplot2::aes(time, dv, group = id)) +
    ggplot2::geom_line(alpha = 0.3) +
    ggplot2::geom_point(alpha = 0.4, size = 0.6) +
    # rows: source vs synthetic. columns: one per endpoint, however many.
    ggplot2::facet_grid(dataset ~ endpoint, scales = "free_y") +
    ggplot2::labs(title = "RESTRICTED: source vs AVATAR synthetic",
                  subtitle = "do not export", x = "Time", y = "DV") +
    ggplot2::theme_bw() +
    ggplot2::theme(legend.position = "none")
  # Concentrations often read better on a log axis. Uncomment if every DV > 0;
  # a log scale drops zeros and negatives.
  # p <- p + ggplot2::scale_y_log10()

  ggplot2::ggsave(file.path(OUT_DIR, "RESTRICTED_source_vs_synthetic.png"), p,
                  width = 4 + 2 * length(unique(compare$endpoint)), height = 6,
                  dpi = 110)
  message("  wrote ", file.path(OUT_DIR, "RESTRICTED_source_vs_synthetic.png"),
          " (restricted; keep in the safe environment)")
  print(p)
} else {
  message("  ggplot2 not available; skipping the diagnostic plot")
}

message("\nDone. The synthetic table carries no formal privacy guarantee; it is ",
        "built by blending real subject trajectories and is for ",
        "trusted-environment use only.")
