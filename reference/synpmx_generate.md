# Draw another dataset from a release already paid for

Generation from an existing release is post-processing: it reads no
confidential data and consumes no additional privacy budget, so any
number of datasets may be drawn from one
[`synpmx_calibrated()`](https://iamstein.github.io/synpmx/reference/synpmx_calibrated.md)
or
[`synpmx_empirical()`](https://iamstein.github.io/synpmx/reference/synpmx_empirical.md)
call.

## Usage

``` r
synpmx_generate(x, n_subjects = NULL, seed = 123, n_datasets = 1L)
```

## Arguments

- x:

  A dataset returned by
  [`synpmx_calibrated()`](https://iamstein.github.io/synpmx/reference/synpmx_calibrated.md)
  or
  [`synpmx_empirical()`](https://iamstein.github.io/synpmx/reference/synpmx_empirical.md),
  or the release itself.

- n_subjects:

  Number of subjects. Defaults to the released noisy count.

- seed:

  Ordinary generation seed.

- n_datasets:

  Number of datasets to draw. One is returned directly; several are
  returned as a list.

## Value

A data frame carrying the same release, or a list of them.

## See also

[`synpmx_calibrated()`](https://iamstein.github.io/synpmx/reference/synpmx_calibrated.md),
[`synpmx_empirical()`](https://iamstein.github.io/synpmx/reference/synpmx_empirical.md)
