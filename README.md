# reportlib

Shared functions and knitr templates for the AIQC in situ CTD summary sites:
[arc-report](https://github.com/AIQC-Hub/arc-report),
[bal-report](https://github.com/AIQC-Hub/bal-report) and
[med-report](https://github.com/AIQC-Hub/med-report).

Each site repo keeps only what is genuinely region-specific — its
`content/_func/common_<region>*.Rmd` constants, its pages, and its
`_quarto.yml`. Everything they had in common lives here.

Not published anywhere. Install from a checkout:

```r
R CMD INSTALL /path/to/reportlib
```

The name is `reportlib` rather than `aiqc-report` because R rejects a hyphen in a
package name at install time — which is why the site repos get away with
`Package: arc-report`: those are never installed, only read as dependency
manifests.

## Layout

| Path | Contents |
|------|----------|
| `R/filters.R` | the standard profile-level filter chain |
| `R/tables.R` | shared table rendering (`kbl_table`, `create_dt_summary_tab`) |
| `R/summary.R` | profile-summary aggregation and region plots |
| `R/var.R` | per-variable summaries |
| `R/qc.R` | IOC QC flag definitions, counts, distributions |
| `R/paths.R` | `template_path()`, `aiqc_data_dir()` |
| `inst/templates/` | the `{{placeholder}}` knitr fragments |

Attaching the package attaches the plotting and table packages the templates
rely on, which is why they are `Depends` rather than `Imports`: template code is
evaluated in the page's environment, not the package's.

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
