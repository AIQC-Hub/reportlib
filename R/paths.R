# Locating the templates and the data directory.

#' Absolute path to one of the packaged templates.
#'
#' Templates are knitr fragments expanded with `knitr::knit_expand()`, so they
#' are read by path rather than rendered by Quarto. Callers name the file:
#' `template_path("var_summary_stats.Rmd")`.
#'
#' @param ... path components under `inst/templates`.
#' @return An absolute path.
#' @export
template_path <- function(...) {
  p <- system.file("templates", ..., package = "aiqcreport")
  if (!nzchar(p)) {
    stop("no such template: ", file.path(...), call. = FALSE)
  }
  p
}

#' The directory holding the profile-summary parquet files.
#'
#' Resolved once to an absolute path, because the working directory a knitr
#' child document runs in is not stable across engines: rmarkdown gave a
#' `child=` document its own directory, Quarto uses the page's. `ARC_DATA_DIR`
#' overrides the search, which is how tooling that runs from elsewhere
#' (`scripts/dump_frames.R`, CI) names the directory outright.
#'
#' The parquet check matters: a bare `dir.exists()` would happily match an
#' unrelated `data` directory further up the tree.
#'
#' @param candidates relative paths to probe, nearest first.
#' @return An absolute path.
#' @export
aiqc_data_dir <- function(candidates = c("../data", "../../data")) {
  from_env <- Sys.getenv("ARC_DATA_DIR", unset = "")
  if (nzchar(from_env)) return(normalizePath(from_env, mustWork = TRUE))
  for (p in candidates) {
    if (dir.exists(p) && length(list.files(p, pattern = "\\.parquet$")) > 0) {
      return(normalizePath(p))
    }
  }
  stop("no data directory with parquet files found, from ", getwd(), call. = FALSE)
}
