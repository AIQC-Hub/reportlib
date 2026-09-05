# The standard profile-level filter chain, applied on every page.
#
# filer_locations_common() keeps the historical spelling: it is called by name
# from every region file in all three report repos.
#
# The location filters were written against observation-level data, where a
# profile spans many rows and its position has to be taken from the first of
# them. build_summaries() now delivers one row per platform x profile, so that
# group_by/summarise/semi_join is a no-op that costs seconds per page (5.9s vs
# 0.2s on nrt_ar). one_row_per_profile() picks the direct filter when the input
# is already profile-level and falls back to the general path when it is not.

one_row_per_profile <- function(df) {
  all(c("platform_code", "profile_no") %in% names(df)) &&
    !vctrs::vec_duplicate_any(df[, c("platform_code", "profile_no")])
}

filter_profile_level_qc <- function(df) {
  df %>% filter((time_qc == 1) & (position_qc %in% c(1, -128)))
}

filer_locations_common <- function(df, min_lon, max_lon, min_lat, max_lat) {
  if (one_row_per_profile(df)) {
    return(df %>% dplyr::filter((longitude >= min_lon) & (longitude <= max_lon) &
                                (latitude >= min_lat) & (latitude <= max_lat)))
  }

  df_filtered <- df %>%
      group_by(platform_code, profile_no) %>%
      summarise(longitude = first(longitude), latitude = first(latitude)) %>%
      ungroup() %>%
      dplyr::filter((longitude >= min_lon) & (longitude <= max_lon) & (latitude >= min_lat) & (latitude <= max_lat)) %>%
      distinct(platform_code, profile_no)

  df %>% semi_join(df_filtered, by=c("platform_code", "profile_no"))
}

exclude_locations_common <- function(df, lon1, lat1, lon2, lat2) {
  if (one_row_per_profile(df)) {
    return(df %>% dplyr::filter(!((longitude >= lon1) & (latitude >= lat1) &
                                  (longitude <= lon2) & (latitude <= lat2))))
  }

  df_filtered <- df %>%
      group_by(platform_code, profile_no) %>%
      summarise(longitude = first(longitude), latitude = first(latitude)) %>%
      ungroup() %>%
      dplyr::filter(!((longitude >= lon1) & (latitude >= lat1) & (longitude <= lon2) & (latitude <= lat2))) %>%
      distinct(platform_code, profile_no)

  df %>% semi_join(df_filtered, by=c("platform_code", "profile_no"))
}

split_time_spans_common <- function(df, ts1, ts1_from, ts1_to, ts2, ts2_from, ts2_to,
                                    ts3, ts3_from, ts3_to, ts4, ts4_from, ts4_to) {
  df_year <- df %>%
    mutate(x = format(profile_timestamp, "%Y"))

  t1 <- df_year %>% filter(x >= ts1_from & x <= ts1_to)
  t2 <- df_year %>% filter(x >= ts2_from & x <= ts2_to)
  t3 <- df_year %>% filter(x >= ts3_from & x <= ts3_to)
  t4 <- df_year %>% filter(x >= ts4_from & x <= ts4_to)

  lst <- list(t1, t2, t3, t4)
  names(lst) = c(ts1, ts2, ts3, ts4)
  lst
}
