# Spec (a) sensitivity: include pre-treatment RAC and WAC trajectories in PSM.
# One common match per cohort/group; exact matching within state, expanded pretreatment histories.
# Controls restricted to never-treated or first placement after 2019; matching algorithm and regression retained.
# Run with LIHTC_EXPANDED_MAIN_OUTPUT set to the separate output directory; see RUN.sh.
library(tidyverse)
library(fixest)
library(MatchIt)
setwd(".")
DATA_PATH <- "data_panels/2010_2019_did_panel_with_seer.csv"
LIHTC_RAW_PATH <- "data_raw/LIHTC/LIHTC_public/LIHTCPUB.csv"
BASE_DIR <- Sys.getenv("LIHTC_REFRESH_OUTPUT")
stopifnot(nchar(BASE_DIR)>0)
PANEL_START <- 2010L
PANEL_END <- 2019L
NEVER_TREATED_COHORT <- 9999L
# available_history: 2011 levels only; 2012 two pre-years; 2013+ three pre-years.
# three_years: restrict eligible treated cohorts to 2013+ (also removes early-treated controls).
HISTORY_POLICY <- Sys.getenv("LIHTC_HISTORY_POLICY", "available_history")
stopifnot(HISTORY_POLICY %in% c("available_history", "three_years"))
dir.create(BASE_DIR, recursive=TRUE, showWarnings=FALSE)
log_connection <- file(file.path(BASE_DIR,"run.log"),open="wt")
sink(log_connection, split=TRUE)
sink(log_connection, type="message")
options(warn=1) # Log numerical warnings immediately beside their cohort/design.
message("Trajectory matching started: ", Sys.time(), "; history policy: ", HISTORY_POLICY)
# ── Load panel ────────────────────────────────────────────────────────────────
message("Loading panel...")
panel <- read_csv(DATA_PATH, show_col_types = FALSE) %>%
  mutate(
    tract_id_num   = as.integer(factor(tract_id)),
    year           = as.integer(year),
    first_pis_year = as.numeric(first_pis_year),
    statea         = sprintf("%02d", as.integer(statea)),
    countya        = sprintf("%03d", as.integer(countya)),
    county_id      = paste0(statea, countya)
  )

# ── Derived variables (same as psm_did_staggered.R) ──────────────────────────
panel <- panel %>%
  mutate(
    log_rac      = log(pmax(rac_total, 1)),
    log_wac      = log(pmax(wac_total, 1)),
    log_rac_low  = log(pmax(rac_earn_le_1250, 1)),
    log_rac_mid  = log(pmax(rac_earn_1251_3333, 1)),
    log_rac_high = log(pmax(rac_earn_ge_3333, 1)),
    log_wac_low  = log(pmax(wac_earn_le_1250, 1)),
    log_wac_mid  = log(pmax(wac_earn_1251_3333, 1)),
    log_wac_high = log(pmax(wac_earn_ge_3333, 1)),
    log_seer_pop = log(pmax(seer_total_population, 1)),
    emp_pop_ratio = rac_total / seer_total_population,

    # Matching covariates
    seer_share_nh_black    = ifelse(seer_total_population > 0, seer_nh_black   / seer_total_population, NA_real_),
    seer_share_nh_aian     = ifelse(seer_total_population > 0, seer_nh_aian    / seer_total_population, NA_real_),
    seer_share_nh_api      = ifelse(seer_total_population > 0, seer_nh_api     / seer_total_population, NA_real_),
    seer_share_hispanic    = ifelse(seer_total_population > 0, seer_hispanic   / seer_total_population, NA_real_),
    seer_age_share_under29 = ifelse(seer_total_population > 0, seer_age_under_29 / seer_total_population, NA_real_),
    seer_age_share_55plus  = ifelse(seer_total_population > 0, seer_age_55_plus  / seer_total_population, NA_real_),
    rac_low_share  = ifelse(rac_total > 0, rac_earn_le_1250 / rac_total, NA_real_),
    rac_high_share = ifelse(rac_total > 0, rac_earn_ge_3333 / rac_total, NA_real_),
    wac_low_share  = ifelse(wac_total > 0, wac_earn_le_1250 / wac_total, NA_real_),
    wac_high_share = ifelse(wac_total > 0, wac_earn_ge_3333 / wac_total, NA_real_),

    # Post-treatment indicator for standard DiD
    post_treatment = ifelse(!is.na(first_pis_year) & year >= first_pis_year, 1L, 0L)
  )

# Treatment eligibility: the source panel defines treatment as TYPE == 1 only.
# Missing timing is not sufficient evidence of never-treatment: remove tracts
# with unknown new-construction timing and no known first placement (328 in the
# current data). Match the original pipeline's FIPS2010 validation exactly.
lihtc_raw <- read_csv(LIHTC_RAW_PATH, col_types = cols(.default = col_character())) %>%
  rename_with(tolower) %>%
  mutate(
    tract_digits = str_replace_all(str_trim(fips2010), "[^0-9]", ""),
    valid_tract = nchar(tract_digits) == 11 &
      between(suppressWarnings(as.integer(substr(tract_digits, 1, 2))), 1L, 56L) &
      substr(tract_digits, 3, 5) != "000" & substr(tract_digits, 6, 11) != "000000",
    pis_year = suppressWarnings(as.numeric(yr_pis))
  )
unknown_newbuild_ids <- lihtc_raw %>%
  filter(valid_tract, str_trim(type) == "1",
         is.na(pis_year) | pis_year %in% c(8888, 9999)) %>%
  transmute(tract_id = as.numeric(tract_digits)) %>%
  distinct()
ambiguous_ids <- panel %>%
  filter(is.na(first_pis_year)) %>%
  distinct(tract_id) %>%
  semi_join(unknown_newbuild_ids, by = "tract_id")
message(sprintf("Excluding %d tracts with unknown new-construction placement timing",
                nrow(ambiguous_ids)))
# Pre-panel cohorts are already treated. The 2010 cohort has no observed
# pre-treatment year, so the estimable treated cohorts are 2011-2019.
panel <- panel %>%
  filter(between(year, PANEL_START, PANEL_END)) %>%
  anti_join(ambiguous_ids, by = "tract_id") %>%
  filter(is.na(first_pis_year) | first_pis_year > PANEL_START) %>%
  mutate(
    is_control = is.na(first_pis_year) | first_pis_year > PANEL_END,
    # Keep source timing intact; sunab drops NA cohorts, so use an out-of-panel
    # sentinel for eligible never-treated tracts. Future cohorts keep their dates.
    cohort_sa = if_else(is.na(first_pis_year),
                        as.numeric(NEVER_TREATED_COHORT), first_pis_year)
  )
stopifnot(!anyNA(panel$cohort_sa), NEVER_TREATED_COHORT > PANEL_END)
message(sprintf("Eligible sample: %d treated tracts; %d shared control tracts",
                n_distinct(panel$tract_id[!panel$is_control]),
                n_distinct(panel$tract_id[panel$is_control])))

# ── Matching covariate sets (same as psm_did_staggered.R) ────────────────────
match_covars_seer <- c(
  "log_seer_pop",
  "seer_share_nh_black", "seer_share_nh_aian",
  "seer_share_nh_api",   "seer_share_hispanic",
  "seer_age_share_under29", "seer_age_share_55plus"
)

match_covars_full <- c(
  match_covars_seer,
  "log_rac", "log_wac",
  "rac_low_share", "rac_high_share",
  "wac_low_share", "wac_high_share"
)

# ── Outcome definitions ──────────────────────────────────────────────────────
outcomes <- list(
  emp_pop_ratio = list(label = "Employment-to-Population Ratio", ylab = "Ratio"),
  log_seer_pop  = list(label = "Log Population (SEER)",          ylab = "Log Points"),
  log_rac       = list(label = "Log Resident-held Jobs",         ylab = "Log Points"),
  log_wac       = list(label = "Log Workplace Jobs",             ylab = "Log Points"),
  log_rac_low   = list(label = "Log Resident-held Jobs, Low-Wage",  ylab = "Log Points"),
  log_rac_mid   = list(label = "Log Resident-held Jobs, Mid-Wage",  ylab = "Log Points"),
  log_rac_high  = list(label = "Log Resident-held Jobs, High-Wage", ylab = "Log Points"),
  log_wac_low   = list(label = "Log Workplace Jobs, Low-Wage",     ylab = "Log Points"),
  log_wac_mid   = list(label = "Log Workplace Jobs, Mid-Wage",     ylab = "Log Points"),
  log_wac_high  = list(label = "Log Workplace Jobs, High-Wage",    ylab = "Log Points")
)


income_median <- median(panel$acs2010_median_hh_income,na.rm=TRUE)
panel <- panel %>% mutate(income_group=case_when(
  is.na(acs2010_median_hh_income) ~ NA_character_,
  acs2010_median_hh_income <= income_median ~ "lower_income", TRUE ~ "higher_income"))
if(HISTORY_POLICY == "three_years") panel <- panel %>% filter(is.na(first_pis_year) | first_pis_year>=2013)
cohorts <- if(HISTORY_POLICY == "three_years") 2013:2019 else 2011:2019
stopifnot(!anyDuplicated(panel[c("tract_id_num","year")]))
# Use endpoints of at most three consecutive PRE-treatment observations.
# For three equally spaced observations, endpoint growth / 2 equals the OLS slope.
# Require all years in that window observed for both outcomes; no imputation.
trajectory<-panel%>%arrange(tract_id_num,year)%>%group_by(tract_id_num)%>%mutate(
 across(c(log_rac,log_wac,log_seer_pop,rac_total,wac_total),list(
 recent=function(v)case_when(year==2011 & lag(year)==2010~v-lag(v),year>=2012 & lag(year,2)==year-2 & is.finite(lag(v))~(v-lag(v,2))/2,TRUE~NA_real_),
 early=function(v)if_else(year>=2014 & lag(year,4)==year-4 & is.finite(lag(v,3)),(lag(v,2)-lag(v,4))/2,NA_real_)
 ),.names='{.col}_{.fn}'))%>%ungroup()%>%select(tract_id_num,year,ends_with('_recent'),ends_with('_early'))
panel<-left_join(panel,trajectory,by=c('tract_id_num','year'))
# Commute outcome only; it does not enter matching.
cm<-arrow::read_parquet('data_panels/od_commute_panel_residence_road.parquet')%>%transmute(tract_id=as.numeric(h_tract),year=as.integer(year),avg_road_dist_from_s000)
stopifnot(!anyDuplicated(cm[c('tract_id','year')]))
panel<-left_join(panel,cm,by=c('tract_id','year'))%>%mutate(log_avg_dist_from_s000=if_else(avg_road_dist_from_s000>0,log(avg_road_dist_from_s000),NA_real_))
outcomes<-c(outcomes,list(rac_total=list(label='Resident-held jobs',ylab='Jobs'),wac_total=list(label='Workplace jobs',ylab='Jobs'),seer_total_population=list(label='Population',ylab='Persons'),log_avg_dist_from_s000=list(label='Commuting distance (log)',ylab='Log points')))
panel <- panel %>% arrange(tract_id_num,year) %>% group_by(tract_id_num) %>% mutate(min_pre_population=cummin(replace_na(seer_total_population,-Inf))) %>% ungroup()
panel <- panel %>% mutate(residential_eligible=!(tract_id %% 1000000>=980000 & tract_id %% 1000000<990000))

sink(type="message");sink();close(log_connection)
panel<-panel%>%mutate(timing=case_when(is.na(first_pis_year)~'never',first_pis_year>2019~'future',TRUE~'treated_2011_2019'))
stopifnot(income_median==51548,nrow(ambiguous_ids)==328)
pp<-read_csv('output/research_extensions/26_main_state_guarded_matching/matched_pairs.csv',show_col_types=FALSE)
stopifnot(all(is.na(pp$first_pis_year[pp$treated_cohort==0])|pp$first_pis_year[pp$treated_cohort==0]>2019))
saveRDS(list(panel=panel,pairs=pp,raw=lihtc_raw,match_covars_full=match_covars_full),file.path(BASE_DIR,'design.rds'))
write_csv(pp,file.path(BASE_DIR,'matched_pairs.csv'))
file.copy('output/research_extensions/26_main_state_guarded_matching/matching_balance.csv',file.path(BASE_DIR,'matching_balance.csv'),overwrite=TRUE)
file.copy('output/research_extensions/26_main_state_guarded_matching/cohort_retention.csv',file.path(BASE_DIR,'cohort_retention.csv'),overwrite=TRUE)
