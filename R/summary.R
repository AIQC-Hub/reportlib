# Profile-summary aggregation and the region plots.

netcdf_summary_1 <- function(df) {
  df %>%
    group_by(platform_code, profile_no) %>%
    summarise(obs_count = sum(observation_no_count), profile_timestamp = first(profile_timestamp),
              longitude = first(longitude), latitude = first(latitude)) %>%
    ungroup()
}

netcdf_summary_2 <- function(df) {
  df %>%
    group_by(platform_code) %>%
    summarise(profile_count = n(),
              min_profile_timestamp = min(profile_timestamp),
              max_profile_timestamp = max(profile_timestamp),
              obs_count = sum(obs_count),
              longitude2 = first(longitude), latitude2 = first(latitude),
              min_longitude = min(longitude), max_longitude = max(longitude),
              min_latitude = min(latitude), max_latitude = max(latitude)) %>%
    ungroup() %>%
    mutate(min_profile_timestamp = format(min_profile_timestamp, "%Y-%m"),
           max_profile_timestamp = format(max_profile_timestamp, "%Y-%m"))
}

netcdf_loc_summary <- function(df) {
  df %>% mutate(d_lon = max_longitude - min_longitude,
                d_lat = max_latitude - min_latitude) %>%
          dplyr::select(`Platform` = platform_code,
                        `# Profiles` = profile_count,
                        `Min(Lon)` = min_longitude,
                        `Max(Lon)` = max_longitude,
                        `Diff(Lon)` = d_lon,
                        `Min(Lat)` = min_latitude,
                        `Max(Lat)` = max_latitude,
                        `Diff(Lat)` = d_lat) %>%
    arrange(desc(`Diff(Lon)`))
}

netcdf_time_location_qc_summary <- function(df) {
  time_qc_count <- df %>%
    count(time_qc) %>%
    rename(`QC flag` = time_qc, `Time QC count` = n)

  position_qc_count <- df %>%
    count(position_qc) %>%
    rename(`QC flag` = position_qc, `Position QC count` = n)

  time_qc_count %>%
    full_join(position_qc_count)%>%
    mutate(
      `Time QC count` = replace_na(`Time QC count`, 0),
      `Position QC count` = replace_na(`Position QC count`, 0)
    ) %>%
    arrange(`QC flag`)
}

create_time_location_qc_summary_tab <- function(df1, df2) {
  platform_n_1 <- df1 %>% distinct(platform_code) %>% nrow()
  profile_n_1 <- df1 %>% distinct(platform_code, profile_no) %>% nrow()
  obs_n_1 <- df1 %>% summarise(n = sum(observation_no_count)) %>% pull(n)

  platform_n_2 <- df2 %>% distinct(platform_code) %>% nrow()
  profile_n_2 <- df2 %>% distinct(platform_code, profile_no) %>% nrow()
  obs_n_2 <- df2 %>% summarise(n = sum(observation_no_count)) %>% pull(n)

  tibble(`Level` = c("Platform", "Profile", "Observation"),
         `Before filtering` = c(platform_n_1, profile_n_1, obs_n_1),
         `After filtering` = c(platform_n_2, profile_n_2, obs_n_2))
}

get_loc_by_platform <- function(df, platform) {
  df %>% filter(platform_code == platform)
}

get_loc_by_timespan <- function(lst, timespan){
  lst %>% pluck(timespan)
}

format_netcdf_summary_2 <- function(df) {
  df %>%
    select(`Platform` = platform_code, `# Profiles` = profile_count,
           From = min_profile_timestamp, To = max_profile_timestamp,
           `# Observations` = obs_count, `Lon` = longitude2, `Lat` = latitude2)
}

create_sample_time_hist <- function(df, title) {
  ggplot(df, aes(x=x)) +
    geom_histogram(stat="count") +
    labs(title = title,
         x = NULL,
         y = "count") + theme_pubr(base_size = 12) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
}

create_obs_count_hist <- function(df, title) {
  ggplot(df, aes(obs_count)) +
    geom_histogram() +
    ggtitle(title) +
    xlab("Observation counts by profile") +
    theme_pubr(base_size = 12)
}

create_region_hist <- function(df, title, xtitle) {
  ggplot(df, aes(x)) +
    geom_histogram() +
    ggtitle(title) +
    xlab(xtitle) +
    theme_pubr(base_size = 12)
}

create_region_scatter <- function(df, title, lat_range, lon_range) {
  if (nrow(df) < 5000) {
    nbins <- 500
  } else {
    nbins <- 1000
  }

  ggplot(df, aes(x = longitude, y = latitude)) +
    annotation_borders("world", fill = "lightgray", color = "gray") +
    geom_hex(bins = nbins) +
    ggtitle(title) +
    xlab("Longitude") +
    ylab("Latitude") +
    coord_cartesian(xlim = lon_range, ylim = lat_range) +
    theme_pubr(base_size = 12)
}
