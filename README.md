# reportlib

Shared functions and knitr templates for the AIQC in situ CTD summary sites:
[arc-report](https://github.com/AIQC-Hub/arc-report),
[bal-report](https://github.com/AIQC-Hub/bal-report) and
[med-report](https://github.com/AIQC-Hub/med-report).

Each site repo keeps only what is genuinely region-specific — its
`content/_func/common_<region>*.Rmd` constants, its pages, and its
`_quarto.yml`. Everything they had in common lives here.

```r
remotes::install_github("AIQC-Hub/reportlib@v0.1.4")
```

The three sites pin that tag, in `DESCRIPTION` and in their build workflows, so a
change here cannot silently alter three published sites. **Tag each release** —
an untagged push leaves the pin unresolvable.

From a checkout, install the dependencies first:

```sh
Rscript tools/install-deps.R      # --check to report without installing
R CMD INSTALL /path/to/reportlib
```

`R CMD INSTALL` does **not** resolve dependencies. It stops at the first missing
one and rolls the whole install back:

```
ERROR: dependency 'maps' is not available for package 'reportlib'
* removing '.../R/x86_64-pc-linux-gnu-library/4.6/reportlib'
```

`tools/install-deps.R` reads the `Depends` and `Imports` below out of
`DESCRIPTION` — there is no second list to keep in step — and installs whatever
is absent from the library of whichever `Rscript` runs it. That last part is the
point on a machine with more than one R: installing "for R" is not a thing,
every install targets one library.

The name is `reportlib` rather than `aiqc-report` because R rejects a hyphen in a
package name at install time — which is why the site repos get away with
`Package: arc-report`: those are never installed, only read as dependency
manifests.

## Dependencies

19 direct, ~156 once CRAN's transitive closure is resolved. Only the direct ones
are declared:

| Package | Used for |
|---------|----------|
| `arrow` | `open_dataset`, `read_parquet`, `write_parquet` — the whole data layer |
| `tidyverse` | ggplot2, dplyr, tidyr, purrr unqualified throughout the templates |
| `data.table` | the chunked aggregation in `build_summaries()` |
| `ggpubr` | `theme_pubr`, `font` |
| `cowplot` | `plot_grid` |
| `scales` | axis and label formatting (`comma`, `percent`, `number`, `alpha`) |
| `maps` | **runtime only** — `ggplot2::borders()` calls `maps::map()` for the region maps |
| `hexbin` | **runtime only** — `geom_hex()` needs it to bin |
| `DT` | `datatable`, `formatRound` — the interactive tables |
| `kableExtra` | `kbl`, `kable_styling` — the static ones |
| `htmltools` | `tags`, `HTML`, `code` in table cells |
| `rlang` | `sym`, `env`, `warn` for the variable-name indirection |
| `digest`, `jsonlite` | `fingerprint_frames()` |
| `dplyr`, `htmlwidgets`, `knitr`, `stats`, `utils` | reached through `::` |

The two marked **runtime only** are the trap: nothing in this repo names them,
because it is ggplot2 that loads them when a plot is drawn. Grepping the source
for package names would drop both, and the failure lands much later, inside a
render, as a missing-package error from a plot.

`fontawesome` was declared until v0.1.2 and is now dropped — a leftover from
Distill, with no call site in any of the four repos.

Dependencies of the sites, not of this package: `rmarkdown` and `yaml` (the
`scripts/*.R` wrappers read `config.yml`). Each site declares those in its own
`DESCRIPTION`.

## Layout

| Path | Contents |
|------|----------|
| `R/filters.R` | the standard profile-level filter chain |
| `R/tables.R` | shared table rendering (`kbl_table`, `create_dt_summary_tab`) |
| `R/summary.R` | profile-summary aggregation and region plots |
| `R/var.R` | per-variable summaries |
| `R/qc.R` | IOC QC flag definitions, counts, distributions |
| `R/paths.R` | `template_path()`, `aiqc_data_dir()` |
| `R/build.R` | `build_summaries()`: seastamp observations to profile summaries |
| `R/fingerprint.R` | `fingerprint_frames()`: per-column digests of what pages read |
| `inst/templates/` | the `{{placeholder}}` knitr fragments |

Attaching the package attaches the plotting and table packages the templates
rely on, which is why they are `Depends` rather than `Imports`: template code is
evaluated in the page's environment, not the package's.

`R CMD check` reports this as a NOTE ("Packages in Depends field not imported
from"). Converting them to `import()` directives would be worse, not better:
`data.table` and `dplyr` both export `first`, `last` and `between`, and the
`Depends` order is what decides the winner. `netcdf_summary_1()` calls
`first(longitude)` and needs dplyr's, which is what the original `libraries.Rmd`
produced by attaching data.table before tidyverse. The remaining check output is
that NOTE, a matching one about undefined globals, and a WARNING that the
exported functions have no `.Rd` files.

## Paths

The package carries no filesystem defaults. `build_summaries()` requires `src_dir`
and `out_dir`, and each site names its own in a `config.yml` at its repo root:

```yaml
data:
  seastamp_dir: /path/to/seastamp/stamped/depth
  summary_dir: /path/to/summaries
```

`SEASTAMP_DIR` and `SUMMARY_DIR` override it. The one path the package does infer
is `aiqc_data_dir()`, which probes `../data` then `../../data` for a directory
containing parquet — that is a repo-layout question, not a machine-specific one,
and it is how the pages reach the summaries through each site's `data` symlink.

## Templates

Referenced by name, not by a registry of `t_*` variables:

```r
src <- knitr::knit_expand(template_path("var_summary_stats.Rmd"),
                          df = df_filtered_name, var = var)
res <- knitr::knit_child(text = src, quiet = TRUE)
cat(res, sep = "\n")
```

## Scope

Everything here is used by at least one of the three sites. The duplicate-detection
functions, `netcdf_time_location_qc_summary` and both `summary_location_filtering*`
templates were dropped once all three had been converted and their call sites went to
zero. `exclude_locations_common` looks unused but is not — med-report's GL region file
calls it twice, to cut two boxes out of the Mediterranean.
