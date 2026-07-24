# Acknowledge the DP engines' unaudited status for this session

[`synpmx_calibrated()`](https://iamstein.github.io/synpmx/reference/synpmx_calibrated.md)
and
[`synpmx_empirical()`](https://iamstein.github.io/synpmx/reference/synpmx_empirical.md)
refuse to run until this has been called at least once in the current
session. This is a deliberate speed bump, not a technical safeguard: the
differentially private engines are complete and tested, but not under
active development, carry known open findings (see
`design/REVIEW_BACKLOG.md`), and have not been independently
privacy-audited. See
[`vignette("synpmx-privacy")`](https://iamstein.github.io/synpmx/articles/synpmx-privacy.md)
for the trust-boundary decision rule and what a production release
additionally needs.
[`synpmx_avatar()`](https://iamstein.github.io/synpmx/reference/synpmx_avatar.md)
and
[`synpmx_prior()`](https://iamstein.github.io/synpmx/reference/synpmx_prior.md)
make no differential-privacy claim and are unaffected.

## Usage

``` r
synpmx_enable_dp_engines()
```

## Value

`TRUE`, invisibly.

## Details

The acknowledgment does not persist. It applies only to the R session it
is called in, so a fresh session, script run, or CI job must call it
again. `backend = "public"` calls make no DP claim either and are exempt
from this gate.

## See also

[`synpmx_disable_dp_engines()`](https://iamstein.github.io/synpmx/reference/synpmx_disable_dp_engines.md)

## Examples

``` r
synpmx_enable_dp_engines()
#> DP engines enabled for this session: the differentially private engines are complete and tested, but not under active development, carry known open findings (see design/REVIEW_BACKLOG.md), and have not been independently privacy-audited. See vignette("synpmx-privacy") for the trust-boundary decision rule and what a production release additionally needs.
```
