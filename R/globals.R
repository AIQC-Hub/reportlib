# Column names and data.table/dplyr symbols referenced by non-standard
# evaluation. Declaring them keeps `R CMD check`'s "no visible binding" notes
# from burying anything real.
utils::globalVariables(c(
  ".", ":=", "Code", "group", "n", "x", "y",
  "platform_code", "profile_no", "profile_timestamp", "time_qc", "position_qc",
  "longitude", "latitude", "longitude2", "latitude2",
  "profile_longitude", "profile_latitude",
  "min_longitude", "max_longitude", "min_latitude", "max_latitude",
  "d_lon", "d_lat", "obs_count", "observation_no_count", "profile_count",
  "min_profile_timestamp", "max_profile_timestamp",
  "min_x", "max_x", "mean_x", "median_x",
  "profile_n", "qc4_prop", "qc4_x",
  "pfs_counts", "pfs_non_na_counts"
))
