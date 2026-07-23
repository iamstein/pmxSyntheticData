# The release behind a generated dataset

Accepts a dataset produced by
[`synpmx_calibrated()`](https://iamstein.github.io/synpmx/reference/synpmx_calibrated.md)
or
[`synpmx_empirical()`](https://iamstein.github.io/synpmx/reference/synpmx_empirical.md)
and returns the release attached to it, or passes a release object
through unchanged. This is what lets `privacy_report(syn)` work on a
dataset.

## Usage

``` r
.release_of(x, what = "x")
```

## Arguments

- x:

  A generated dataset, or a release object.

- what:

  Human-readable description of the caller, used in errors.

## Value

A `pmx_calibrated_model` or `private_pmx_model`.
