# IOC QC flag definitions, counts and distributions.

get_flag_def <- function() {
  Code <- c("0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A")
  Definition <- c("No QC was performed",
                  "Good data",
                  "Probably good data",
                  "Bad data that are potentially correctable",
                  "Bad data",
                  "Value changed",
                  "Below detection limit",
                  "In excess of quoted value",
                  "Interpolated value",
                  "Missing value",
                  "Incomplete information")

  tibble(Code, Definition)
}

get_flag_counts <- function(df, var) {
  flag_counts <- df %>%
    select(platform_code, profile_no, starts_with(var)) %>%
    pivot_longer(
      cols = starts_with(var),
      names_to = "Code",
      names_prefix = paste0(var, "_"),
      values_to = "profile_n"
    ) %>%
    group_by(Code) %>%
    summarise(n = sum(profile_n)) %>%
    select(Code, n)

  get_flag_def() %>%
    left_join(flag_counts, by="Code") %>%
    mutate(n = ifelse(is.na(n), 0, n),
           `Relative Frequency (%)` = scales::percent(n / sum(n), accuracy = 0.1),
           n = comma(n))
}

qc_summary_1 <- function(df, var) {
  df %>%
    select(platform_code, profile_no, starts_with(var)) %>%
    pivot_longer(
      cols = starts_with(var),
      names_to = "Code",
      names_prefix = paste0(var, "_"),
      values_to = "profile_n"
    ) %>%
    group_by(platform_code, Code) %>%
    summarise(n = sum(profile_n)) %>%
    ungroup() %>%
    complete(platform_code, Code, fill = list(count = 0)) %>%
    mutate(n = ifelse(is.na(n), 0, n)) %>%
    pivot_wider(names_from = Code, values_from = n) %>%
    select(where(~ !all(.x == 0)))
}

format_qc_summary_1 <- function(df) {
  df %>%
    rename(`Platform` = platform_code)
}

qc_summary_time <- function(df, var) {
  df %>%
    select(platform_code, profile_no, x, starts_with(var)) %>%
    pivot_longer(
      cols = starts_with(var),
      names_to = "Code",
      names_prefix = paste0(var, "_"),
      values_to = "profile_n"
    ) %>%
    group_by(x, Code) %>%
    summarise(n = sum(profile_n)) %>%
    ungroup() %>%
    complete(x, Code, fill = list(count = 0)) %>%
    mutate(n = ifelse(is.na(n), 0, n)) %>%
    pivot_wider(names_from = Code, values_from = n) %>%
    select(where(~ !all(.x == 0)))
}

qc4_proportion <- function(df, var_x) {
  col_count <- sym(paste0(var_x, "_count"))
  col_qc4 <- sym(paste0(var_x, "_qc_4"))

  df %>%
    select(platform_code,
           profile_timestamp,
           profile_no,
           n = !!col_count,
           qc4_x = !!col_qc4) %>%
    mutate(qc4_prop = qc4_x / n)
}

create_qc4_density <- function(df, main_title) {
  ggplot(df, aes(x=qc4_prop)) +
    geom_density(alpha=0.25, size = 0.25)  +
    labs(x = "proportion of QC 4",
         y = "density") +
    theme_pubr(base_size = 12) +
    ggtitle(main_title) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
}

format_qc_summary_year <- function(df) {
  df %>%
    rename(`Year` = x)
}

format_qc_summary_month <- function(df) {
  df %>%
    rename(`Month` = x)
}
