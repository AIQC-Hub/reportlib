# Shared table rendering.

kbl_table <- function(x) {
  kbl(x, format.args = list(big.mark = ",")) %>%
    kable_styling(bootstrap_options = c("striped", "hover", "condensed", "responsive"))
}

# Common funcitons

create_dt_summary_tab <- function(df, cols=c('Lon', 'Lat')) {
  DT::datatable(df, rownames = FALSE,
      options = list(searching = TRUE, paging = TRUE, info = TRUE,
                     lengthMenu = list(c(10, 50, 100, -1), c("10", "50", "100", "All")))) %>%
    formatRound(columns = cols, digits = 1) %>%
    htmlwidgets::prependContent(tags$style(HTML('table.dataTable {font-size: 12px;}')))
}

na_summary <- function(df, var) {
  count_col <- sym(paste0(var, "_count"))
  na_col <- sym(paste0(var, "_na_count"))
  non_na_col <- sym(paste0(var, "_non_na_count"))

  df_obs <- df %>%
    summarise(obs_tot = sum(!!count_col), obs_non_na = sum(!!non_na_col),
              .groups = "drop")

  df_profs <- df %>%
    summarise(
      profs_tot = n(),
      profs_non_na = sum(if_else(!!na_col > 0, 0, 1)),
      .groups = "drop"
    )

  df_pfs <- df %>%
    group_by(platform_code) %>%
    summarise(pfs_counts = sum(!!count_col),
              pfs_na_counts = sum(!!na_col),
              pfs_non_na_counts = sum(!!non_na_col), .groups = "drop") %>%
    summarise(
      pfs_tot = n(),
      pfs_non_na = sum(pfs_counts == pfs_non_na_counts),
      .groups = "drop"
    )

  tibble(
    Level = c("Platform", "Profile", "Observation"),
    `Total Count` = c(df_pfs$pfs_tot, df_profs$profs_tot, df_obs$obs_tot),
    `Non-NA Count` = c(df_pfs$pfs_non_na, df_profs$profs_non_na, df_obs$obs_non_na)
  ) %>%
    mutate(
      `Pct` = percent(`Non-NA Count` / `Total Count`, accuracy = 0.1),
      `Total Count` = comma(`Total Count`),
      `Non-NA Count` = comma(`Non-NA Count`)
    )
}
