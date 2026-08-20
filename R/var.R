# Per-variable summaries (temperature, salinity).

var_summary_1 <- function(df, var_x) {
  col_min <- sym(paste0(var_x, "_min"))
  col_max <- sym(paste0(var_x, "_max"))
  col_mean <- sym(paste0(var_x, "_mean"))
  col_median <- sym(paste0(var_x, "_median"))
  col_count <- sym(paste0(var_x, "_count"))

  df %>%
    group_by(platform_code) %>%
    summarise(n = sum(!!col_count),
              min_x = min(!!col_min),
              median_x = median(!!col_median),
              mean_x = mean(!!col_mean),
              max_x = max(!!col_max)) %>%
    ungroup()
}

format_var_summary_1 <- function(df, var_name) {
  df %>%
    select(`Platform` = platform_code, `# Obs` = n,
           `Min(X)` = min_x, `Median(X)` = median_x, `Mean(X)` = mean_x, `Max(X)` = max_x) %>%
    rename_with(~ gsub("X", var_name, .x, fixed = TRUE))
}

var_summary_2 <- function(df, var_x) {
  col_min <- sym(paste0(var_x, "_min"))
  col_max <- sym(paste0(var_x, "_max"))
  col_mean <- sym(paste0(var_x, "_mean"))
  col_median <- sym(paste0(var_x, "_median"))
  col_count <- sym(paste0(var_x, "_count"))

  df %>%
    select(platform_code,
           profile_timestamp,
           profile_no,
           n = !!col_count,
           min_x = !!col_min,
           median_x = !!col_median,
           mean_x = !!col_mean,
           max_x =!!col_max)
}

create_var_boxplot <- function(df, y_title) {
  df <- df %>% select(x, Min=min_x, Max=max_x, Mean=mean_x, Median=median_x) %>%
    pivot_longer(!x, names_to = "group", values_to = "y") %>%
    mutate(group = factor(group, levels=c("Min", "Max", "Mean", "Median")))

  ggplot(df, aes(x=x, y=y)) +
    geom_boxplot(outlier.size = 0.1) +
    facet_wrap(vars(group), ncol = 1, scales = "free") +
    labs(x = NULL,
         y = y_title) +
    theme_pubr(base_size = 12) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
}
