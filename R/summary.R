# Profile-summary aggregation and the region plots.

# Reducing to one row per platform x profile. The grouped form below is what
# observation-level input needs; on the profile-level summaries the sites now
# read, every group has exactly one row and the grouping costs 15s per page
# against 0.01s for the direct transform (nrt_ar, 295k profiles). Both produce
# the same frame, sorted by platform and profile, so the fast path arranges.
netcdf_summary_1 <- function(df) {
  if (one_row_per_profile(df)) {
    return(df %>%
      transmute(platform_code, profile_no, obs_count = observation_no_count,
                profile_timestamp, longitude, latitude) %>%
      arrange(platform_code, profile_no))
  }

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

# Back to the original bin counts. 300 was a speed compromise, and it changed
# what the map says: at 1000 the individual cruise tracks stay legible, at 300
# they smooth into coverage blobs. `freeze: auto` in the sites pays the cost on
# a real change rather than on every rebuild, so the resolution can be chosen
# for the reader again.
REGION_SCATTER_BINS <- c(small = 500, large = 1000)

# Longitude and latitude are not the same unit on the ground: a degree of
# longitude is cos(latitude) as long as a degree of latitude. Letting the panel
# stretch to whatever the figure device happens to be is what made the maps
# look wrong, most visibly in the Arctic where the distortion is largest.
# Fixing the ratio at 1/cos(mean latitude) gives each region its natural shape
# and leaves the unused part of the device as margin. The clamp keeps the ratio
# finite for a range centred on the pole.
region_aspect <- function(lat_range) {
  1 / cos(min(abs(mean(lat_range)), 85) * pi / 180)
}

create_region_scatter <- function(df, title, lat_range, lon_range) {
  nbins <- if (nrow(df) < 5000) {
    REGION_SCATTER_BINS[["small"]]
  } else {
    REGION_SCATTER_BINS[["large"]]
  }

  # Note that `bins` divides the *scale* range, and annotation_borders() puts the
  # whole world on the scale, so a bin is 360/nbins degrees of longitude wide
  # whatever the region -- about 0.36 degrees at 1000, roughly 40km, the same
  # cell everywhere. That reads as accidental but it is the behaviour to keep:
  # binning across each region's own range instead was measured and it makes the
  # Baltic 1km cells, which at 1920px are single specks on an empty map.
  ggplot(df, aes(x = longitude, y = latitude)) +
    annotation_borders("world", fill = "lightgray", color = "gray") +
    geom_hex(bins = nbins) +
    ggtitle(title) +
    xlab("Longitude") +
    ylab("Latitude") +
    coord_fixed(ratio = region_aspect(lat_range), xlim = lon_range, ylim = lat_range) +
    theme_pubr(base_size = 12) +
    # The default key is about an inch wide, which ran the count labels into
    # each other ("500 100015002000").
    theme(legend.key.width = grid::unit(5, "cm"),
          legend.key.height = grid::unit(0.4, "cm"))
}
