# Generate a dataset from public inputs only

Simulates from a public structural model and a public protocol. No
confidential data is read, so there is nothing to protect and no budget
to spend: this is `epsilon = 0`, the strongest possible guarantee.

## Usage

``` r
synpmx_prior(
  model,
  design,
  n_subjects = NULL,
  seed = NULL,
  dropout = 0,
  lloq = NULL,
  covariates = NULL
)
```

## Arguments

- model:

  A
  [`pmx_structural_model()`](https://iamstein.github.io/synpmx/reference/pmx_structural_model.md).

- design:

  A
  [`pmx_trial_design()`](https://iamstein.github.io/synpmx/reference/pmx_trial_design.md).

- n_subjects:

  Number of subjects. Defaults to the planned cohort total.

- seed:

  Ordinary generation seed. Unrelated to privacy noise.

- dropout:

  Fraction of subjects who discontinue early. A public assumption from
  the protocol.

- lloq:

  Lower limit of quantification. Observations below it are flagged
  `CENS = 1` with `DV` at the limit, following the Monolix convention.

- covariates:

  Optional
  [`pmx_covariates()`](https://iamstein.github.io/synpmx/reference/pmx_covariates.md).

## Value

A data frame in the generated event-table schema; see
[`pmx_generated_roles()`](https://iamstein.github.io/synpmx/reference/pmx_generated_roles.md).

## Details

The typical parameter values must come from somewhere that is not the
data – allometric scaling from preclinical work, a published model for
the compound class, or the reasoning that set the starting dose. The
output is exactly as good as that prior.

## See also

[`synpmx_avatar()`](https://iamstein.github.io/synpmx/reference/synpmx_avatar.md),
[`synpmx_calibrated()`](https://iamstein.github.io/synpmx/reference/synpmx_calibrated.md),
[`synpmx_empirical()`](https://iamstein.github.io/synpmx/reference/synpmx_empirical.md)

## Examples

``` r
model <- pmx_structural_model(
  pk = "1cmt_oral", typical = c(cl = 6, v = 35, ka = 1.5),
  source = "illustrative allometric scaling"
)
design <- pmx_trial_design(
  dose_levels = 320, cohort_sizes = 12, sampling = c(0, 1, 2, 4, 9, 24),
  source = "illustrative protocol"
)
syn <- synpmx_prior(model, design, n_subjects = 12, seed = 202)
head(syn, 3)
#>   ID      TIME NTIME       TAD OCC       DV AMT RATE EVID CMT DVID MDV CENS
#> 1  1 0.0000000     0 0.0000000   1       NA 320    0    1   1 <NA>   1    0
#> 2  1 0.0000000     0 0.0000000   1 0.000000   0    0    0   2   cp   0    0
#> 3  1 0.9791034     1 0.9791034   1 6.823022   0    0    0   2   cp   0    0
#>   DOSE
#> 1  320
#> 2  320
#> 3  320
```
