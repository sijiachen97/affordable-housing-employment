suppressPackageStartupMessages({library(tidyverse);library(fixest)})
BASE_DIR<-Sys.getenv('LIHTC_REFRESH_OUTPUT');x<-readRDS(file.path(BASE_DIR,'design.rds'));panel<-x$panel;match_covars_full<-x$match_covars_full
PANEL_END<-2019;cohorts<-2011:2019
it<-panel%>%filter(year==first_pis_year,between(first_pis_year,2011,2019))%>%transmute(tract_id,intensity=if_else(seer_total_population>0,n_new_units_total/seer_total_population*1000,NA_real_))
cutoff<-median(it$intensity[is.finite(it$intensity)])
it<-it%>%mutate(intensity_group=case_when(!is.finite(intensity)~NA_character_,intensity<=cutoff~'low_intensity',TRUE~'high_intensity'))
stopifnot(sum(is.finite(it$intensity))==2615)
panel<-left_join(panel,it,by='tract_id');x$panel<-panel;saveRDS(x,file.path(BASE_DIR,'design.rds'))
write_csv(it,file.path(BASE_DIR,'intensity_definition.csv'));writeLines(paste('Frozen full-eligible-treated median:',cutoff),file.path(BASE_DIR,'intensity_cutoff.txt'))
all_pairs_out<-list();all_retention<-list();all_balance<-list();treated_retention<-list()
for(group in c('low_intensity','high_intensity')){
 group_panel<-panel%>%filter(is_control|intensity_group==group)
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
all_pairs_out[[group]]<-pairs
}
write_csv(bind_rows(all_pairs_out),file.path(BASE_DIR,'intensity_matched_pairs.csv'));write_csv(bind_rows(all_retention),file.path(BASE_DIR,'intensity_retention.csv'));write_csv(bind_rows(all_balance),file.path(BASE_DIR,'intensity_balance.csv'))
