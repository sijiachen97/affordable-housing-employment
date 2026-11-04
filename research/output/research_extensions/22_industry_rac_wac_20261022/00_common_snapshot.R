# Shared definitions for the three sequential extension analyses.
# Source only: no estimation is triggered here. Original paper files are read-only.
suppressPackageStartupMessages({library(tidyverse); library(fixest); library(arrow)})
ROOT <- Sys.getenv('LIHTC_PROJECT_ROOT','.')
OUT <- Sys.getenv('LIHTC_EXTENSION_OUTPUT',file.path(ROOT,'output/research_extensions'))
path <- function(...) file.path(ROOT,...)
CHECK_ONLY <- Sys.getenv('LIHTC_EXTENSION_ESTIMATE','0') != '1'
dir.create(OUT,recursive=TRUE,showWarnings=FALSE)
A_DIR <- path('output/robustness_specs/event_study/spec_a_county_trajectory_matching')
load_design <- function() {
 p <- read_csv(path('data_panels/2010_2019_did_panel_with_seer.csv'),show_col_types=FALSE) %>%
  mutate(tract_id=as.numeric(tract_id),year=as.integer(year),
   tract_id_num=as.integer(factor(tract_id)),county_id=sprintf('%02d%03d',as.integer(statea),as.integer(countya)))
 stopifnot(!anyDuplicated(p[c('tract_id','year')]))
 raw <- read_csv(path('data_raw/LIHTC/LIHTC_public/LIHTCPUB.csv'),col_types=cols(.default=col_character())) %>%
  rename_with(tolower) %>% mutate(digits=str_replace_all(str_trim(fips2010),'[^0-9]',''),
   valid=nchar(digits)==11 & between(suppressWarnings(as.integer(substr(digits,1,2))),1L,56L) &
    substr(digits,3,5)!='000' & substr(digits,6,11)!='000000',
   tract_id=suppressWarnings(as.numeric(digits)),pis=suppressWarnings(as.numeric(yr_pis))) %>%
  filter(valid,str_trim(type)=='1')
 unknown <- raw %>% filter(is.na(pis)|pis %in% c(8888,9999)) %>% distinct(tract_id)
 # Reconstruct treatment timing from new construction, independently of panel NA.
 known <- raw %>% filter(!is.na(pis),!pis %in% c(8888,9999)) %>%
  group_by(tract_id) %>% summarise(raw_first=min(pis),.groups='drop')
 compare <- p %>% distinct(tract_id,first_pis_year) %>% left_join(known,by='tract_id')
 stopifnot(nrow(compare)==n_distinct(p$tract_id),
  all((is.na(compare$first_pis_year)&is.na(compare$raw_first))|
   (!is.na(compare$first_pis_year)&!is.na(compare$raw_first)&compare$first_pis_year==compare$raw_first)))
 ambiguous <- compare %>% filter(is.na(first_pis_year)) %>% semi_join(unknown,by='tract_id')
 write_csv(ambiguous,file.path(OUT,'excluded_unknown_timing.csv'))
 p <- p %>% filter(between(year,2010,2019)) %>% anti_join(ambiguous,by='tract_id') %>%
  filter(is.na(first_pis_year)|first_pis_year>2010) %>%
  mutate(cohort_sa=if_else(is.na(first_pis_year),9999,first_pis_year),
   timing=case_when(is.na(first_pis_year)~'never',first_pis_year>2019~'future',TRUE~'treated_2011_2019'),
   log_rac=log(pmax(rac_total,1)),emp_pop_ratio=if_else(seer_total_population>0,rac_total/seer_total_population,NA_real_))
 cutoff <- median(p$acs2010_median_hh_income,na.rm=TRUE) # Preserve paper's row-weighted definition.
 p <- p %>% mutate(income_group=case_when(is.na(acs2010_median_hh_income)~NA_character_,
  acs2010_median_hh_income<=cutoff~'lower_income',TRUE~'higher_income'))
 audit <- p %>% distinct(tract_id,timing) %>% count(timing,name='tracts')
 write_csv(audit,file.path(OUT,'eligible_tract_audit.csv'))
 # Freeze the current data version: changes require investigation, never silently proceed.
 stopifnot(nrow(ambiguous)==328,cutoff==51548,
  sum(audit$tracts[audit$timing=='never'])==58087,
  sum(audit$tracts[audit$timing=='future'])==817,
  sum(audit$tracts[audit$timing=='treated_2011_2019'])==2618,!anyNA(p$cohort_sa))
 pairs <- read_csv(file.path(A_DIR,'matched_pairs.csv'),show_col_types=FALSE)
 pp <- pairs %>% select(group,match_id,tract_id,cohort,treated_cohort) %>%
  left_join(p %>% distinct(tract_id,county_id,first_pis_year,income_group),by='tract_id')
 stopifnot(!anyNA(pp$county_id),!anyDuplicated(pp[c('group','match_id','tract_id')]),
  all(is.na(pp$first_pis_year)|pp$first_pis_year>2010),
  all(pp$first_pis_year[pp$treated_cohort==1]==pp$cohort[pp$treated_cohort==1]),
  all(is.na(pp$first_pis_year[pp$treated_cohort==0])|
   pp$first_pis_year[pp$treated_cohort==0]>pp$cohort[pp$treated_cohort==0]),
  all(pp$group=='pooled'|(!is.na(pp$income_group)&pp$group==pp$income_group)))
 qa <- pp %>% group_by(group,match_id) %>% summarise(n=n(),nt=sum(treated_cohort),nc=n_distinct(county_id),.groups='drop')
 stopifnot(all(qa$n==2),all(qa$nt==1),all(qa$nc==1),
  sum(qa$group=='pooled')==2153,sum(qa$group=='lower_income')==1215,sum(qa$group=='higher_income')==790)
 write_csv(pp %>% mutate(control_status=case_when(treated_cohort==1~'focal_treated',
  is.na(first_pis_year)~'never',first_pis_year>2019~'future',TRUE~'later_treated_within_panel')) %>%
  count(group,control_status),file.path(OUT,'frozen_matching_audit.csv'))
 writeLines(c(paste('Income cutoff',cutoff),paste('Pairs MD5',tools::md5sum(file.path(A_DIR,'matched_pairs.csv'))),
  'Never cohorts = 9999; future dates retained; all <=2010 excluded.',
  'Matching controls untreated at focal cohort date, NOT necessarily throughout 2010-2019.',
  'Reuse across cohorts retained; cluster original tract; no rematching.',capture.output(sessionInfo())),file.path(OUT,'configuration.txt'))
 list(panel=p,pairs=pairs,raw=raw)
}
fit_model <- function(d,y,fe) feols(as.formula(paste(y,'~ sunab(cohort_sa,year,ref.p=c(-1,.F)) |',fe)),data=d,cluster=~tract_id_num)
# All outcomes within an analysis use common complete rows. B uses EXACT A fitted rows.
run_models <- function(panel,pairs,outcomes,groups,folder) {
 dir.create(folder,recursive=TRUE,showWarnings=FALSE)
 att<-list();cf<-list();au<-list();pt<-list();miss<-list()
 save_fit <- function(f,d,y,g,s) {
  u<-d[fixest::obs(f),]; a<-aggregate(f,'ATT'); key<-paste(g,s,y,sep='_')
  stopifnot(!anyNA(u$cohort_sa),all(is.na(u$first_pis_year)|u$first_pis_year>2010),
   any(is.na(u$first_pis_year)),any(between(u$first_pis_year,2011,2019),na.rm=TRUE))
  att[[key]] <<- tibble(group=g,specification=s,outcome=y,estimate=a[1,1],std_error=a[1,2],p_value=a[1,4],observations=nobs(f))
  cc<-as.data.frame(coeftable(f)); names(cc)<-c('estimate','std_error','t_stat','p_value')
  cc<-rownames_to_column(cc,'term') %>% mutate(group=g,specification=s,outcome=y)
  cf[[key]] <<- cc
  # Checkpoint new results only; estimator and sample definitions unchanged.
  write_csv(bind_rows(att),file.path(folder,"att_checkpoint.csv"))
  au[[key]] <<- tibble(group=g,specification=s,outcome=y,input_rows=nrow(d),used_rows=nrow(u),
   unique_tract_years=nrow(distinct(u,tract_id,year)),tracts=n_distinct(u$tract_id),
   never_tracts=n_distinct(u$tract_id[is.na(u$first_pis_year)]),
   future_tracts=n_distinct(u$tract_id[u$timing=='future']),
   treated_tracts=n_distinct(u$tract_id[u$timing=='treated_2011_2019']),treated_by_2010=0)
  write_csv(u %>% select(any_of(c('tract_id','year','match_id','cohort_sa','timing'))),file.path(folder,paste0('sample_',key,'.csv.gz')))
  for(w in c('displayed','all')) {
   z<-wald(f,keep=if(w=='displayed')'year::-[2-5]:' else 'year::-[2-8]:',print=FALSE)
   if(!is.list(z)) stop('No pretrend restrictions found: ',key)
   pt[[paste(key,w)]] <<- tibble(group=g,specification=s,outcome=y,window=w,p_value=z$p,df=z$df1)
  }
 }
 for(g in groups) {
  full<-if(g=='pooled') panel else filter(panel,income_group==g)
  miss[[g]]<-full %>% group_by(timing,year) %>% summarise(rows=n(),
    across(all_of(outcomes),~sum(!is.finite(.x)),.names='missing_{.col}'),.groups='drop') %>% mutate(group=g)
  full<-full %>% filter(if_all(all_of(outcomes),is.finite))
  d<-pairs %>% filter(group==g) %>% select(tract_id,match_id) %>%
   inner_join(full,by='tract_id',relationship='many-to-many') %>% mutate(match_id_num=as.integer(factor(match_id)))
  # Recursively remove singleton FE observations once using first outcome.
  anchor<-fit_model(d,outcomes[1],'tract_id_num + match_id_num^year')
  d<-d[fixest::obs(anchor),]
  anchor_c<-fit_model(full,outcomes[1],'tract_id_num + county_id^year')
  full<-full[fixest::obs(anchor_c),]
  for(y in outcomes) {
   message(g,' / ',y)
   for(s in c('matched_pair_year','full_county_year','matched_year')) {
    dd<-if(s=='full_county_year')full else d
    fe<-switch(s,matched_pair_year='tract_id_num + match_id_num^year',full_county_year='tract_id_num + county_id^year',matched_year='tract_id_num + year')
    f<-fit_model(dd,y,fe)
    stopifnot(identical(as.integer(fixest::obs(f)),seq_len(nrow(dd))))
    save_fit(f,dd,y,g,s)
   }
  }
 }
 at<-bind_rows(att); co<-bind_rows(cf)
 write_csv(at,file.path(folder,'att_long.csv'));write_csv(co,file.path(folder,'event_study_coefficients.csv'))
 write_csv(bind_rows(au),file.path(folder,'estimation_sample_audit.csv'));write_csv(bind_rows(miss),file.path(folder,'missing_outcome_audit.csv'))
 write_csv(bind_rows(pt),file.path(folder,'pretrend_tests.csv'))
 wide<-at %>% mutate(cell=sprintf('%.4f%s (%.4f)',estimate,case_when(p_value<.01~'***',p_value<.05~'**',p_value<.1~'*',TRUE~''),std_error)) %>%
  select(group,outcome,specification,cell) %>% pivot_wider(names_from=specification,values_from=cell) %>%
  select(group,outcome,matched_pair_year,full_county_year,matched_year)
 write_csv(wide,file.path(folder,'did_wide.csv'))
 tex<-c('\\begin{tabular}{llccc}','\\hline','Group & Outcome & (1) & (2) & (3) \\\\', '\\hline',
  apply(as.data.frame(wide),1,function(r)paste0(paste(gsub('_',' ',r,fixed=TRUE),collapse=' & '),' \\\\')),
  '\\hline','\\end{tabular}',
  '% (1) Matched sample: tract and pair-year FE. (2) Full sample: tract and county-year FE. (3) Same rows as (1): tract and year FE.',
  '% SE clustered by original tract; ***, **, * indicate 1%, 5%, 10%. ATT averages all supported post-treatment horizons.')
 writeLines(tex,file.path(folder,'did_table.tex'))
 for(y in outcomes) {
  z<-co %>% filter(outcome==y) %>% mutate(event=as.numeric(sub('year::','',term))) %>% filter(between(event,-5,5))
  z<-bind_rows(z,distinct(z,group,specification,outcome) %>% mutate(event=-1,estimate=0,std_error=0)) %>%
   mutate(specification=factor(specification,levels=c('matched_pair_year','full_county_year','matched_year'),labels=c('(1) Matched: pair-year FE','(2) Full: county-year FE','(3) Matched: year FE')))
  p<-ggplot(z,aes(event,estimate))+geom_hline(yintercept=0,color='grey60')+geom_vline(xintercept=-1,linetype=2,color='grey60')+
   geom_errorbar(aes(ymin=estimate-1.96*std_error,ymax=estimate+1.96*std_error),width=0,color='#214F80')+
   geom_line(color='#214F80')+geom_point(color='#214F80',size=1)+facet_grid(group~specification)+
   theme_bw(base_size=11)+theme(panel.grid.minor=element_blank(),panel.grid.major=element_line(linetype='dotted',color='grey90'))+
   labs(x='Years relative to first placement',y=y,title=gsub('_',' ',y))
  ggsave(file.path(folder,paste0('eventstudy_',y,'.png')),p,width=12,height=max(4,3*length(groups)),dpi=180)
 }
 invisible(list(att=at,coefficients=co))
}
