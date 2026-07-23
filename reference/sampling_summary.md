# Summarize the fitted sampling design

Returns post-processed, privacy-accounted sampling summaries from a
fitted model. For dose-relative and occasion endpoints, the summary
separates the probability that an occasion is sampled from the mean
number of observations conditional on sampling. It never consults the
source data.

## Usage

``` r
sampling_summary(private_model)
```

## Arguments

- private_model:

  A model returned by
  [`.fit_private()`](https://iamstein.github.io/synpmx/reference/dot-fit_private.md).

## Value

A data frame with one row per endpoint and possible dose occasion.
