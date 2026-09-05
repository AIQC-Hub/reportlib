# Building the profile-level summaries the sites read.

#' Build profile-level summary parquet from seastamp observation-level parquet.
#'
#' The sites read pre-aggregated summaries, one row per platform x profile.
#' `ctddump` + `seastamp` emit observation-level parquet, so this is the layer
#' between them. It replaces the ad-hoc R that produced the pre-2026 summaries.
#'
#' Idempotent: a dataset is skipped when every output already exists and is
#' newer than its source.
#'
#' Three properties of the seastamp data are handled here, each of which fails
#' silently if missed. QC flags are strings (`"1"`, `"4"`, `""`) where the filter
#' chain compares numerically. A blank flag means a missing value (verified 1:1
#' against NA values), counted as `blank_flag`. And `profile_longitude` /
#' `profile_latitude` are unpopulated, so position comes from the
#' observation-level columns -- preferring the profile ones yields NaN
#' coordinates that the location filter then drops.
#'
#' Memory: aggregating the largest dataset (~118M rows) in one pass needs well
#' over 10 GB, so platforms are binned into chunks of about `chunk_rows` rows. A
#' profile never spans platforms, so any partition by platform is a valid
#' partition of the groups. Exact medians are why this is not pushed into arrow,
#' whose grouped `median()` is approximate.
#'
#' @param datasets list of `list(src=, out=)`: seastamp basename and summary stem.
#' @param src_dir directory holding the seastamp parquet. Required: the package
#'   deliberately holds no filesystem defaults, so each site names its own paths
#'   (in `config.yml`) rather than inheriting one machine's layout.
#' @param out_dir directory to write the summaries into. Required, as above.
#' @param vars variables summarised in the base table.
#' @param qc_vars variables to also emit QC 1 / QC 4 subsets for.
#' @param chunk_rows approximate observation rows to hold in memory at once.
#' @param blank_flag IOC code to count a blank flag as; "9" is "Missing value".
#' @param force rebuild even when the outputs are current.
#' @param only optional character vector of `src` names to restrict the run to.
#' @export
build_summaries <- function(datasets,
                            src_dir,
                            out_dir,
                            vars = c("temp", "psal", "pres"),
                            qc_vars = c("temp", "psal", "pres"),
                            chunk_rows = 15e6,
                            blank_flag = "9",
                            force = FALSE,
                            only = character()) {

  if (missing(src_dir) || missing(out_dir)) {
    stop("src_dir and out_dir are required; name them in the site's config.yml",
         call. = FALSE)
  }

  qc_subsets <- c(qc1 = 1L, qc4 = 4L)
  # IOC QC flags, in the order get_flag_def() expects.
  FLAGS <- c("0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A")
  BLANK_FLAG <- blank_flag

  if (length(only) > 0) {
    datasets <- Filter(function(d) d$src %in% only, datasets)
    if (length(datasets) == 0) stop("no dataset matches: ", paste(only, collapse = ", "))
  }

  # --- aggregation helpers ---------------------------------------------------

  # min/max over an all-NA group return -Inf/Inf with a warning; NA is what the
  # templates expect and what the old summaries carried.
  smin    <- function(x) if (all(is.na(x))) NA_real_ else as.numeric(min(x, na.rm = TRUE))
  smax    <- function(x) if (all(is.na(x))) NA_real_ else as.numeric(max(x, na.rm = TRUE))
  smean   <- function(x) if (all(is.na(x))) NA_real_ else as.numeric(mean(x, na.rm = TRUE))
  smedian <- function(x) if (all(is.na(x))) NA_real_ else as.numeric(stats::median(x, na.rm = TRUE))
  # First non-missing value, for the per-profile identity columns.
  # x[NA_integer_] rather than x[[1L]] for the empty case: data.table evaluates
  # `j` once on a zero-row prototype to learn the column types, and x[[1L]] is a
  # subscript error there. This is reached when a QC subset is empty.
  firstna <- function(x) {
    i <- which(!is.na(x))
    if (length(i)) x[[i[[1L]]]] else if (length(x)) x[[1L]] else x[NA_integer_]
  }

  # Per-variable statistics, as a fragment of a data.table `j` expression.
  stat_code <- function(v, col = v) sprintf(
    "%1$s_count = .N,
     %1$s_na_count = sum(is.na(%2$s)),
     %1$s_non_na_count = sum(!is.na(%2$s)),
     %1$s_mean = smean(%2$s),
     %1$s_median = smedian(%2$s),
     %1$s_min = smin(%2$s),
     %1$s_max = smax(%2$s)", v, col)

  # Flag counts, one column per IOC code.
  flag_code <- function(v) paste(
    sprintf("%1$s_qc_%2$s = sum(%1$s_flag == %3$dL)", v, FLAGS, seq_along(FLAGS) - 1L),
    collapse = ",\n   ")

  identity_code <- "profile_timestamp = profile_timestamp[1L],
     time_qc = time_qc[1L],
     position_qc = position_qc[1L],
     longitude = firstna(longitude),
     latitude = firstna(latitude)"

  agg <- function(dt, j) {
    dt[, eval(parse(text = paste0("list(", j, ")"))), by = .(platform_code, profile_no)]
  }

  # --- per-chunk work --------------------------------------------------------

  read_chunk <- function(src, platforms) {
    cols <- c("platform_code", "profile_no", "profile_timestamp",
              "time_qc", "position_qc", "longitude", "latitude",
              "profile_longitude", "profile_latitude",
              vars, paste0(vars, "_qc"))
    dt <- open_dataset(src) |>
      filter(platform_code %in% platforms) |>
      select(all_of(cols)) |>
      collect() |>
      as.data.table()

    # The site's filter chain compares these numerically
    # (`time_qc == 1 & position_qc %in% c(1, -128)`), so they must not stay strings.
    dt[, time_qc := as.integer(time_qc)]
    dt[, position_qc := as.integer(position_qc)]

    # Position comes from the observations, as it always has. seastamp also carries
    # profile_longitude / profile_latitude, but they are unpopulated -- all null
    # across nrt_ar_ar -- so they serve only as a fallback. Preferring them silently
    # produced NaN coordinates, which the location filter then dropped entirely.
    dt[, longitude := fifelse(is.na(longitude), profile_longitude, longitude)]
    dt[, latitude  := fifelse(is.na(latitude),  profile_latitude,  latitude)]
    dt[, c("profile_longitude", "profile_latitude") := NULL]

    # Flags -> 0-based index into FLAGS, so counting is integer comparison.
    for (v in vars) {
      qc <- paste0(v, "_qc")
      dt[, (paste0(v, "_flag")) := {
        x <- get(qc)
        x[is.na(x) | x == ""] <- BLANK_FLAG
        match(x, FLAGS) - 1L
      }]
      dt[, (qc) := NULL]
    }
    dt
  }

  summarise_chunk <- function(dt) {
    # Only the count: the mean, median, min and max of an observation number
    # within a profile describe the numbering, not the data, and no page reads
    # them. `.N` is the same count stat_code() computed.
    base_j <- paste(c(identity_code, "observation_no_count = .N",
                      unlist(lapply(vars, function(v) paste(stat_code(v), flag_code(v), sep = ",\n   ")))),
                    collapse = ",\n   ")
    out <- list(base = agg(dt, base_j))

    for (v in qc_vars) {
      for (nm in names(qc_subsets)) {
        sub <- dt[get(paste0(v, "_flag")) == qc_subsets[[nm]]]
        key <- paste0(nm, "_", v)
        # Written even when the subset is empty. nrt_mo has no QC 4 pressure
        # observation at all, and skipping the file there left the page reading
        # a parquet that did not exist. data.table returns a correctly typed
        # zero-row frame, so the site loads it and the templates take their
        # no-data branch.
        out[[key]] <- agg(
          sub, paste(identity_code, "observation_no_count = .N", stat_code(v), sep = ",\n   ")
        )
      }
    }
    out
  }

  # --- driver ----------------------------------------------------------------

  outputs_for <- function(d) {
    c(file.path(out_dir, paste0(d$out, ".parquet")),
      as.vector(outer(names(qc_subsets), qc_vars,
                      function(q, v) file.path(out_dir, sprintf("%s_%s_%s.parquet", d$out, q, v)))))
  }

  build <- function(d) {
    src   <- file.path(src_dir, paste0(d$src, ".parquet"))
    outs  <- outputs_for(d)
    if (!file.exists(src)) stop("missing source: ", src)

    if (!force && all(file.exists(outs)) &&
        min(file.mtime(outs)) > file.mtime(src)) {
      message("== ", d$src, ": up to date, skipping")
      return(invisible(NULL))
    }

    message("== ", d$src)
    ds     <- open_dataset(src)
    counts <- ds |> count(platform_code) |> collect() |> arrange(desc(n))

    # Greedy bin-packing of platforms into chunks: a profile never spans platforms,
    # so any partition by platform is a valid partition of the groups.
    chunks <- list(); cur <- character(); cur_n <- 0
    for (i in seq_len(nrow(counts))) {
      if (cur_n > 0 && cur_n + counts$n[i] > chunk_rows) {
        chunks[[length(chunks) + 1L]] <- cur; cur <- character(); cur_n <- 0
      }
      cur <- c(cur, counts$platform_code[i]); cur_n <- cur_n + counts$n[i]
    }
    if (length(cur)) chunks[[length(chunks) + 1L]] <- cur

    message(sprintf("   %s rows, %d platforms, %d chunk(s)",
                    format(sum(counts$n), big.mark = ","), nrow(counts), length(chunks)))

    acc <- list()
    for (i in seq_along(chunks)) {
      t0 <- Sys.time()
      res <- summarise_chunk(read_chunk(src, chunks[[i]]))
      for (k in names(res)) acc[[k]] <- c(acc[[k]], list(res[[k]]))
      message(sprintf("   chunk %d/%d  %d platforms  %.0fs",
                      i, length(chunks), length(chunks[[i]]),
                      as.numeric(difftime(Sys.time(), t0, units = "secs"))))
    }

    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    for (k in names(acc)) {
      df <- rbindlist(acc[[k]])
      setorder(df, platform_code, profile_no)
      # Identity columns first, matching the layout the templates were written against.
      setcolorder(df, c("platform_code", "profile_no", "profile_timestamp",
                        "time_qc", "position_qc", "longitude", "latitude"))
      path <- if (k == "base") file.path(out_dir, paste0(d$out, ".parquet"))
              else file.path(out_dir, sprintf("%s_%s.parquet", d$out, k))
      write_parquet(df, path)
      message(sprintf("   -> %-52s %10s rows  %d cols",
                      basename(path), format(nrow(df), big.mark = ","), ncol(df)))
    }
  }

  for (d in datasets) build(d)
  invisible(NULL)
}
