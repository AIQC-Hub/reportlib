# Duplicate-profile detection.
#
# Unused by arc-report since its duplicate sections were removed, but still
# called by bal-report and med-report. Retire when those are converted.

find_duplicates_within_platforms <- function(df) {
  df %>%
    distinct(platform_code, profile_timestamp, profile_no, longitude, latitude) %>%
    mutate(lon2 = round(longitude, 3),
           lat2 = round(latitude, 3)) %>%
    arrange(platform_code, profile_timestamp, profile_no, lon2, lat2) %>%
    group_by(platform_code, profile_timestamp, lon2, lat2) %>%
    summarise(profile_nos = paste0(profile_no, collapse = ","),
              n = n(),
              n2 = length(unique(platform_code))) %>%
    ungroup() %>%
    filter((n > 1) & (n2 == 1))
}

summarise_df_dup_within <- function(df_orig, df_dup) {
  df_orig  %>%
    select(platform_code, profile_timestamp, profile_no, longitude, latitude,
           observation_no_count, pres_mean, temp_mean, psal_mean) %>%
    mutate(lon2 = round(longitude, 3),
           lat2 = round(latitude, 3)) %>%
    arrange(platform_code, profile_timestamp, profile_no, lon2, lat2) %>%
    inner_join(df_dup %>% dplyr::select(-c(profile_nos, n, n2)),
               by=c("platform_code", "profile_timestamp", "lon2", "lat2")) %>%
    ungroup()
}

find_duplicates_across_platforms <- function(df) {
  df %>%
    distinct(platform_code, profile_timestamp, profile_no, longitude, latitude) %>%
    mutate(lon2 = round(longitude, 3),
           lat2 = round(latitude, 3)) %>%
    arrange(platform_code, profile_timestamp, profile_no, longitude, latitude) %>%
    group_by(profile_timestamp, lon2, lat2) %>%
    summarise(platform_codes = paste0(platform_code, collapse = ","),
              profile_nos = paste0(profile_no, collapse = ","),
              n = n(),
              n2 = length(unique(platform_code))) %>%
    filter((n > 1) & (n2 > 1)) %>%
    arrange(profile_timestamp, lon2, lat2)
}

summarise_df_dup_across <- function(df_orig, df_dup) {
  df_dup2 <- df_dup %>%
    mutate(
      platform_code = str_split(platform_codes, ","),
      profile_no = str_split(profile_nos, ",")
    ) %>%
    select(platform_code, profile_no) %>%
    unnest(c(platform_code, profile_no)) %>%
    mutate(profile_no = as.integer(profile_no))

  df_orig  %>%
    select(platform_code, profile_timestamp, profile_no, longitude, latitude,
           observation_no_count, pres_mean, temp_mean, psal_mean) %>%
    mutate(lon2 = round(longitude, 3),
           lat2 = round(latitude, 3)) %>%
    arrange(platform_code, profile_timestamp, profile_no, longitude, latitude) %>%
    inner_join(df_dup2) %>%
    arrange(profile_timestamp, lon2, lat2)
}
