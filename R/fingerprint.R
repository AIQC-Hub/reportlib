# Fingerprinting the frames the pages read.

#' Fingerprint every data frame the site's pages load.
#'
#' Later phases must not change what the pages read, and a wrong number buried
#' in a rendered table is the failure mode hardest to spot by eye. This records
#' per-column digests plus the headline figures, so a diff names the column that
#' moved rather than just reporting that something did.
#'
#' It uses the *real* code -- this package for the filter chain, and the site's
#' own `_func/*.Rmd` region files via `knitr::purl()` -- so it cannot drift into
#' validating a reimplementation of itself.
#'
#' @param datasets named list of `list(common=, vars=)`: the region file under
#'   `func_dir`, and the variables whose QC subsets the pages load.
#' @param func_dir the site's `content/_func` directory.
#' @param data_dir directory holding the summary parquet.
#' @param out_dir directory for the `*.json` fingerprints.
#' @param check compare against what is already in `out_dir` instead of writing.
#' @param site_common site-level child sourced before each region file.
#' @return `TRUE` if everything matched (always `TRUE` when `check` is `FALSE`).
#' @export
fingerprint_frames <- function(datasets, func_dir, data_dir, out_dir,
                               check = FALSE, site_common = "common_site.Rmd") {
  func_dir <- normalizePath(func_dir, mustWork = TRUE)
  data_dir <- normalizePath(data_dir, mustWork = TRUE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  # --- helpers ---------------------------------------------------------------

  # Source an .Rmd's code chunks into `env`, exactly as knitr would run them.
  source_rmd <- function(rmd, env) {
    r <- tempfile(fileext = ".R")
    on.exit(unlink(r), add = TRUE)
    knitr::purl(file.path(func_dir, rmd), output = r, documentation = 0L, quiet = TRUE)
    sys.source(r, envir = env, keep.source = FALSE)
    invisible(env)
  }

  # Per-column digests, so a diff names the column that moved rather than just
  # reporting that something did. The frame digest is derived from them, which also
  # sidesteps data.frame attribute noise (tibble vs data.frame, row names).
  fingerprint <- function(df) {
    df  <- as.data.frame(df)
    key <- intersect(c("platform_code", "profile_no"), names(df))
    if (length(key) > 0) df <- df[do.call(order, unname(as.list(df[key]))), , drop = FALSE]
    rownames(df) <- NULL

    col_digest <- vapply(names(df), function(n) digest::digest(df[[n]], algo = "xxhash64"), character(1))
    cols <- lapply(names(df), function(n) {
      list(name = n, type = class(df[[n]])[1], digest = unname(col_digest[[n]]))
    })

    # Figures that appear on the rendered pages, so a diff is human-readable before
    # anyone reaches for the hashes.
    stats <- list(rows = nrow(df))
    if ("platform_code" %in% names(df)) stats$platforms <- n_distinct(df$platform_code)
    if (all(c("platform_code", "profile_no") %in% names(df))) {
      stats$profiles <- nrow(distinct(df, platform_code, profile_no))
    }
    obs <- grep("^observation_no_count$", names(df), value = TRUE)
    if (length(obs) == 1) stats$observations <- sum(df[[obs]], na.rm = TRUE)

    list(
      digest  = digest::digest(paste(names(df), col_digest, collapse = "|"), algo = "xxhash64"),
      stats   = stats,
      ncol    = ncol(df),
      columns = cols
    )
  }

  # --- build the frames ------------------------------------------------------

  collect <- function(id, spec) {
    env <- new.env(parent = globalenv())
    # aiqc_data_dir() probes relative to the working directory; this script runs
    # from the repo root, so name the directory outright.
    Sys.setenv(ARC_DATA_DIR = data_dir)
    source_rmd(site_common, env)   # release_url, rsc_dir
    source_rmd(spec$common, env)         # region constants; loads the base frame

    out <- list()
    df  <- get(env$df_name, envir = env)
    out[[env$df_name]] <- fingerprint(df)

    # The standard chain, as the location_filtering.Rmd template applies it.
    # filer_locations()/exclude_locations() are the region wrappers from common_ar*.Rmd.
    filtered <- df |>
      filter_profile_level_qc() |>
      env$filer_locations() |>
      env$exclude_locations()
    out[[env$df_filtered_name]] <- fingerprint(filtered)

    for (var in spec$vars) {
      for (qc in c("qc1", "qc4")) {
        # Same gsub() as the load_qc_summary.Rmd template, kept verbatim so the harness
        # reproduces production's filename construction rather than a tidied version.
        stem <- get(paste0("parquet_", qc), envir = env)
        f    <- file.path(data_dir, gsub(".parquet", paste0("_", var, ".parquet"), stem))
        qdf  <- read_parquet(f)

        base <- paste0(env$df_name, "_", qc, "_", var)
        out[[base]] <- fingerprint(qdf)
        out[[paste0(base, "_filtered")]] <- fingerprint(
          qdf |> filter_profile_level_qc() |> env$filer_locations() |> env$exclude_locations()
        )
      }
    }
    out
  }

  # --- run -------------------------------------------------------------------

  status <- 0L
  for (id in names(datasets)) {
    message("== ", id)
    fp   <- collect(id, datasets[[id]])
    path <- file.path(out_dir, paste0(id, ".json"))
    json <- jsonlite::toJSON(fp, auto_unbox = TRUE, pretty = TRUE, digits = NA)

    for (nm in names(fp)) {
      s <- fp[[nm]]$stats
      message(sprintf("   %-32s %10s rows  %s", nm, format(s$rows, big.mark = ","), fp[[nm]]$digest))
    }

    if (check) {
      if (!file.exists(path)) {
        message("   MISSING baseline: ", path); status <- 1L
      } else if (identical(readLines(path, warn = FALSE), strsplit(json, "\n")[[1]])) {
        message("   OK -- matches baseline")
      } else {
        message("   DRIFT vs baseline: ", path); status <- 1L
      }
    } else {
      writeLines(json, path)
    }
  }

  # Environment recorded separately: it is useful context but would otherwise make
  # every frame file diff whenever a package is upgraded.
  if (!check) {
    writeLines(jsonlite::toJSON(list(
      generated  = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      git_commit = tryCatch(system2("git", c("-C", dirname(dirname(func_dir)), "rev-parse", "HEAD"),
                                    stdout = TRUE), error = function(e) NA),
      aiqcreport = as.character(utils::packageVersion("aiqcreport")),
      R          = paste(R.version$major, R.version$minor, sep = "."),
      arrow      = as.character(utils::packageVersion("arrow")),
      dplyr      = as.character(utils::packageVersion("dplyr")),
      data_dir   = data_dir
    ), auto_unbox = TRUE, pretty = TRUE), file.path(out_dir, "_env.json"))
  }

  invisible(status == 0L)
}
