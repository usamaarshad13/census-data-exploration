# Census and population data exploration
# Run from the repository root: Rscript analysis.R

required_packages <- c("tidyverse")
missing_packages <- required_packages[!vapply(required_packages, requireNamespace,
                                               logical(1), quietly = TRUE)]
if (length(missing_packages) > 0) {
  stop("Install required package(s): ", paste(missing_packages, collapse = ", "))
}
suppressPackageStartupMessages(library(tidyverse))

dir.create("images", showWarnings = FALSE)

# 1. Adult income dataset: inspect numeric and categorical distributions.
adult <- read_csv("data/adult.csv", show_col_types = FALSE,
                  na = c("", "NA", "?")) |>
  mutate(across(where(is.character), str_trim))

adult |> select(age, `education-num`, `hours-per-week`, `capital-gain`,
                `capital-loss`) |> summary()
adult |> count(sex, `income-bracket`)

adult_distributions <- bind_rows(
  adult |> transmute(value = `education-num`, variable = "Education level"),
  adult |> transmute(value = `hours-per-week`, variable = "Hours per week")
) |>
  ggplot(aes(x = value)) +
  geom_histogram(bins = 24, fill = "#3973ac", color = "white") +
  facet_wrap(~ variable, scales = "free_x") +
  labs(title = "Numeric distributions in the Adult dataset",
       x = NULL, y = "Number of records") +
  theme_minimal(base_size = 12)
ggsave("images/adult-distributions.svg", adult_distributions,
       width = 10, height = 4.5)

income_by_sex <- adult |>
  filter(!is.na(sex), !is.na(`income-bracket`)) |>
  count(sex, `income-bracket`) |>
  group_by(sex) |>
  mutate(proportion = n / sum(n)) |>
  ggplot(aes(x = sex, y = proportion, fill = `income-bracket`)) +
  geom_col(width = 0.62) +
  scale_y_continuous(labels = scales::percent) +
  scale_fill_manual(values = c("<=50K" = "#3973ac", ">50K" = "#e07b39")) +
  labs(title = "Income bracket mix by sex",
       x = NULL, y = "Share of records", fill = "Annual income") +
  theme_minimal(base_size = 12)
ggsave("images/income-by-sex.svg", income_by_sex, width = 7, height = 4.5)

# Pairwise view of numeric variables. A fixed seed makes the sample reproducible.
set.seed(441)
numeric_sample <- adult |>
  select(age, fnlwgt, `education-num`, `capital-gain`, `capital-loss`,
         `hours-per-week`) |>
  slice_sample(n = min(1000, n()))
svg("images/numeric-pairs.svg", width = 8, height = 8)
pairs(numeric_sample, main = "Pairwise relationships in a sample of Adult records")
dev.off()

# 2. Combine alternating-year population tables and make year columns.
population_even <- read_csv("data/population_even.csv", show_col_types = FALSE)
population_odd <- read_csv("data/population_odd.csv", show_col_types = FALSE)

population <- full_join(population_even, population_odd,
                        by = c("STATE", "NAME")) |>
  rename_with(~ str_remove(.x, "^POPESTIMATE"), starts_with("POPESTIMATE")) |>
  select(STATE, NAME, all_of(as.character(2010:2019))) |>
  arrange(NAME)

# Interpolate internal gaps using adjacent years. The source's Wisconsin 2019
# cell is absent at the end of the series, so restore the Vintage 2020 Census
# estimate (5,822,434) instead of carrying forward the 2018 value.
for (year in 2011:2018) {
  missing <- is.na(population[[as.character(year)]])
  if (any(missing)) {
    population[[as.character(year)]][missing] <- rowMeans(
      cbind(population[[as.character(year - 1)]][missing],
            population[[as.character(year + 1)]][missing]), na.rm = TRUE)
  }
}
population$`2019`[population$NAME == "Wisconsin"] <- 5822434

stopifnot(!anyNA(population[as.character(2010:2019)]))

# Per-geography maximum and sum of annual population estimates. The latter is
# a person-year total across ten observations, not a population count.
population_summary <- population |>
  rowwise() |>
  mutate(max_annual_population = max(c_across(all_of(as.character(2010:2019)))),
         person_years_2010_2019 = sum(c_across(all_of(as.character(2010:2019))))) |>
  ungroup() |>
  select(STATE, NAME, max_annual_population, person_years_2010_2019)
print(population_summary)

# Trend chart for three selected states.
state_trends <- population |>
  filter(NAME %in% c("California", "Illinois", "New York")) |>
  pivot_longer(cols = all_of(as.character(2010:2019)),
               names_to = "year", values_to = "population") |>
  mutate(year = as.integer(year))

state_population_plot <- ggplot(state_trends,
                                aes(year, population / 1e6,
                                    color = NAME, group = NAME)) +
  geom_line(linewidth = 1) + geom_point(size = 2) +
  scale_x_continuous(breaks = 2010:2019) +
  scale_color_manual(values = c("California" = "#3973ac",
                                "Illinois" = "#e07b39",
                                "New York" = "#4b9b75")) +
  labs(title = "Selected state population estimates, 2010–2019",
       x = "Year", y = "Estimated population (millions)", color = "State") +
  theme_minimal(base_size = 12) +
  theme(axis.text.x = element_text(angle = 35, hjust = 1))
ggsave("images/state-population-trends.svg", state_population_plot,
       width = 9, height = 5)

# The files contain the 50 states, Washington, D.C., and Puerto Rico. This sum
# combines all listed geographies and must not be labeled the U.S. population.
combined_geography_estimate_2019 <- sum(population$`2019`)
message("2019 sum across the 50 states, D.C., and Puerto Rico: ",
        format(combined_geography_estimate_2019, big.mark = ","))
