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
BASE_DIR <- Sys.getenv("LIHTC_EXPANDED_MAIN_OUTPUT")
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
labels <- c(pooled="All tracts",lower_income="Lower-income tracts",higher_income="Higher-income tracts")
all_att <- list(); all_balance <- list(); all_retention <- list(); all_pretests <- list()
all_pairs_out <- list(); all_coefficients <- list(); treated_retention <- list()
fit_model <- function(ov,fit_data) {
  feols(as.formula(paste0(ov," ~ sunab(cohort_sa, year, ref.p=c(-1,.F)) | tract_id_num + match_id_num^year")),
        data=fit_data,cluster=~tract_id_num)
}
for(group in names(labels)) {
  message("\n=== ",group," ===")
  group_panel <- if(group=="pooled") panel else filter(panel,income_group==group)
  pair_list <- list()
  for(g in cohorts) {
    growth_covars<-c(if(g>=2012)paste0(c('log_rac','log_wac','log_seer_pop','rac_total','wac_total'),'_recent') else character(),if(g>=2015)paste0(c('log_rac','log_wac','log_seer_pop','rac_total','wac_total'),'_early') else character())
    covars <- c(match_covars_full,growth_covars)
    candidates <- group_panel %>% filter(year==g-1) %>% mutate(treated_cohort=case_when(
      first_pis_year==g ~ 1L,is.na(first_pis_year)|first_pis_year>PANEL_END ~ 0L,TRUE ~ NA_integer_)) %>%
      filter(!is.na(treated_cohort), residential_eligible, min_pre_population>=100)
    levels_complete <- candidates %>% drop_na(all_of(match_covars_full))
    eligible <- levels_complete %>% drop_na(all_of(growth_covars))
    stopifnot(all(eligible$year==g-1),all(is.na(eligible$first_pis_year)|eligible$first_pis_year>=g))
    message("Matching trajectories: ",group," / ",g)
    # Same propensity model, descending treated-score greedy nearest matching.
    # Hard covariate constraints are applied BEFORE selecting a control.
    stopifnot(all(is.finite(as.matrix(eligible[,covars]))))
    f_ps<-glm(as.formula(paste('treated_cohort ~',paste(covars,collapse='+'))),data=eligible,family=binomial())
    stopifnot(f_ps$converged)
    ps<-fitted(f_ps);tr<-which(eligible$treated_cohort==1);co<-which(eligible$treated_cohort==0)
    pc<-.2*sqrt((var(ps[tr])+var(ps[co]))/2)
    core<-c('log_seer_pop','log_rac','log_wac',growth_covars)
    X<-as.matrix(eligible[,core]);sdT<-apply(X[tr,,drop=FALSE],2,sd)
    stopifnot(all(is.finite(sdT)));tol<-ifelse(sdT>1e-10,sdT,1e-10)
    Z<-sweep(X,2,tol,'/');used_control<-integer();chosen<-list()
    for(k in tr[order(-ps[tr],eligible$tract_id[tr])]){
      cc<-setdiff(co[eligible$statea[co]==eligible$statea[k]],used_control)
      cc<-cc[abs(ps[cc]-ps[k])<=pc]
      if(length(cc)){
        dif<-abs(sweep(Z[cc,,drop=FALSE],2,Z[k,],'-'));cc<-cc[apply(dif,1,max)<=1+1e-10]
      }
      if(length(cc)) cc<-cc[abs(eligible$log_seer_pop[cc]-eligible$log_seer_pop[k])<=log(3)+1e-12 & abs(eligible$log_rac[cc]-eligible$log_rac[k])<=log(5)+1e-12 & abs(eligible$log_wac[cc]-eligible$log_wac[k])<=log(5)+1e-12]
      if(!length(cc))next
      j<-cc[order(abs(ps[cc]-ps[k]),eligible$tract_id[cc])][1]
      used_control<-c(used_control,j);ss<-length(chosen)+1L
      chosen[[ss]]<-eligible[c(k,j),]%>%mutate(subclass=as.character(ss))
      stopifnot(max(abs(Z[k,]-Z[j,]))<=1+1e-10)
    }
    md<-bind_rows(chosen);stopifnot(nrow(md)>0)
    pairs <- md %>% select(tract_id_num,tract_id,statea,county_id,first_pis_year,treated_cohort,subclass) %>%
      mutate(cohort=g,group=group,match_id=paste0(group,"_c",g,"_p",subclass))
    stopifnot(all(is.na(pairs$first_pis_year[pairs$treated_cohort==0]) | pairs$first_pis_year[pairs$treated_cohort==0]>PANEL_END))
    stopifnot(all((pairs %>% count(match_id))$n==2),
              all((pairs %>% group_by(match_id) %>% summarise(n=sum(treated_cohort)))$n==1))
    stopifnot(all((pairs %>% group_by(match_id) %>% summarise(n=n_distinct(statea)))$n==1))
    pair_list[[as.character(g)]] <- pairs
    retention <- tibble(group=group,cohort=g,pre_year_start=max(2010,g-3),pre_year_end=g-1,
      trajectory_in_matching=g>=2012,
      total_treated=n_distinct(group_panel$tract_id_num[group_panel$first_pis_year %in% g]),
      baseline_treated=sum(candidates$treated_cohort==1),
      levels_complete_treated=sum(levels_complete$treated_cohort==1),
      trajectory_complete_treated=sum(eligible$treated_cohort==1),
      matched_treated=sum(md$treated_cohort==1),eligible_controls=sum(eligible$treated_cohort==0))
    control_counties <- unique(eligible$statea[eligible$treated_cohort==0])
    retention$eligible_treated_without_state_control <- sum(eligible$treated_cohort==1 & !eligible$statea %in% control_counties)
    treated_retention[[paste(group,g)]] <- candidates %>% filter(treated_cohort==1) %>%
      select(tract_id,tract_id_num,statea,county_id) %>% mutate(group=group,cohort=g,
        levels_complete=tract_id_num %in% levels_complete$tract_id_num,
        trajectory_complete=tract_id_num %in% eligible$tract_id_num,
        state_has_eligible_control=statea %in% control_counties,
        matched=tract_id_num %in% pairs$tract_id_num[pairs$treated_cohort==1])
    all_retention[[paste(group,g)]] <- retention
    message("Cohort ",g,": ",retention$matched_treated," matched / ",retention$total_treated,
            " treated; trajectory predictors: ",g>=2012)
    for(cv in covars){
      den<-sd(eligible[[cv]][tr]);if(!is.finite(den)||den<1e-10)den<-NA_real_
      all_balance[[paste(group,g,cv)]]<-bind_rows(lapply(c('before','after'),function(st){dd<-if(st=='before')eligible else md;tibble(group=group,cohort=g,covariate=cv,stage=st,treated_mean=mean(dd[[cv]][dd$treated_cohort==1]),control_mean=mean(dd[[cv]][dd$treated_cohort==0]),smd=(mean(dd[[cv]][dd$treated_cohort==1])-mean(dd[[cv]][dd$treated_cohort==0]))/den)}))
    }


  }
  pairs <- bind_rows(pair_list)
  all_pairs_out[[group]] <- pairs
  pair_panel <- pairs %>% select(tract_id_num,match_id) %>%
    inner_join(group_panel,by="tract_id_num",relationship="many-to-many") %>%
    mutate(match_id_num=as.integer(factor(match_id)))
  dest <- file.path(BASE_DIR,group)
  dir.create(file.path(dest,"figures"),recursive=TRUE,showWarnings=FALSE)
  dir.create(file.path(dest,"coefficients"),recursive=TRUE,showWarnings=FALSE)
  for(ov in names(outcomes)) {
    message("Estimating ",group," / ",ov)
    fit <- fit_model(ov,pair_panel)
    used <- pair_panel[fixest::obs(fit),]
    stopifnot(!anyNA(used$cohort_sa),all(is.na(used$first_pis_year)|used$first_pis_year>2010),
      !any(used$tract_id %in% ambiguous_ids$tract_id),
      all(used$cohort_sa[is.na(used$first_pis_year)]==9999))
    a <- aggregate(fit,"ATT")
    stopifnot(all(is.finite(a)))
    key <- paste(group,ov)
    all_att[[key]] <- tibble(group=group,outcome=ov,specification="spec_a_psm_pair_fe_state_guarded_clean_controls",
      estimate=a[1,1],std_error=a[1,2],p_value=a[1,4],observations=nrow(used),
      tracts=n_distinct(used$tract_id),never_treated_tracts=n_distinct(used$tract_id[is.na(used$first_pis_year)]),
      future_treated_tracts=n_distinct(used$tract_id[!is.na(used$first_pis_year) & used$first_pis_year>2019]),
      treated_by_2010_tracts=sum(!is.na(used$first_pis_year)&used$first_pis_year<=2010))
    cf <- as.data.frame(coeftable(fit)) %>% rownames_to_column("term") %>%
      rename(estimate=Estimate,std_error=`Std. Error`,t_stat=`t value`,p_value=`Pr(>|t|)`) %>%
      mutate(group=group,outcome=ov)
    all_coefficients[[key]] <- cf
    write_csv(cf,file.path(dest,"coefficients",paste0("coef_",ov,".csv")))
    png(file.path(dest,"figures",paste0("eventstudy_",ov,".png")),width=1000,height=700,res=120)
    iplot(fit,ref.line=-1,xlim=c(-5,5),
      main=paste(outcomes[[ov]]$label,labels[[group]],"Spec (a): State + covariate guards",sep="\n"),
      xlab="Years relative to first LIHTC placement",ylab=outcomes[[ov]]$ylab)
    dev.off()
    for(window in c("all_leads","displayed_leads")) {
      w <- wald(fit,keep=if(window=="all_leads") "year::-[2-8]:" else "year::-[2-5]:",print=FALSE)
      all_pretests[[paste(key,window)]] <- tibble(group=group,outcome=ov,window=window,
        statistic=w$stat,p_value=w$p,df1=w$df1,df2=w$df2)
    }
  }
}
att <- bind_rows(all_att); balance <- bind_rows(all_balance); retention <- bind_rows(all_retention)
stopifnot(nrow(att)==length(outcomes)*3,nrow(retention)==length(cohorts)*3,all(att$never_treated_tracts>0))
write_csv(bind_rows(treated_retention),file.path(BASE_DIR,"treated_retention_detail.csv"))
write_csv(att,file.path(BASE_DIR,"sunab_att.csv"))
write_csv(balance,file.path(BASE_DIR,"matching_balance.csv"))
write_csv(retention,file.path(BASE_DIR,"cohort_retention.csv"))
write_csv(bind_rows(all_pretests),file.path(BASE_DIR,"pretrend_tests.csv"))
write_csv(bind_rows(all_pairs_out),file.path(BASE_DIR,"matched_pairs.csv"))
# Combined income figures use the same limits for both panels, computed from CIs.
for(ov in names(outcomes)) {
  cf <- bind_rows(all_coefficients) %>% filter(outcome==ov,group!="pooled") %>%
    mutate(event=as.numeric(sub("year::","",term))) %>% filter(between(event,-5,5))
  cf <- bind_rows(cf,tibble(group=c("lower_income","higher_income"),event=-1,estimate=0,std_error=0))
  cf <- cf %>% mutate(group=factor(group,levels=c("lower_income","higher_income")))
  p <- ggplot(cf,aes(event,estimate))+geom_hline(yintercept=0,color="grey50")+
    geom_vline(xintercept=-1,linetype=2)+geom_errorbar(aes(ymin=estimate-1.96*std_error,
    ymax=estimate+1.96*std_error),width=.15)+geom_point()+
    facet_wrap(~group,labeller=as_labeller(labels))+scale_x_continuous(breaks=-5:5)+theme_bw()+
    labs(title=outcomes[[ov]]$label,subtitle="Spec (a): State + covariate guards",
      x="Years relative to first LIHTC placement",y=outcomes[[ov]]$ylab)
  dir.create(file.path(BASE_DIR,"income_combined"),showWarnings=FALSE)
  ggsave(file.path(BASE_DIR,"income_combined",paste0("eventstudy_income_",ov,".png")),p,
         width=12,height=5,dpi=150)
}
writeLines(c(paste("History policy:",HISTORY_POLICY),paste("Income median:",income_median),
  capture.output(sessionInfo())),file.path(BASE_DIR,"run_configuration.txt"))
message("Completed successfully: ",Sys.time())
sink(type="message");sink();close(log_connection)

