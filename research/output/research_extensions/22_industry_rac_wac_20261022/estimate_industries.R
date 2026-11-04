# All 20 LODES industry sectors, pooled RAC and WAC, frozen paper matches.
# Usage: Rscript estimate_industries.R rac (or wac). No paper outputs are changed.
W<-dirname(normalizePath(sub('^--file=', '', commandArgs()[grepl('^--file=', commandArgs())][1])))
side<-commandArgs(trailingOnly=TRUE)[1];stopifnot(side %in% c('rac','wac'))
Sys.setenv(LIHTC_EXTENSION_OUTPUT=file.path(W,side))
source(file.path(W,'00_common_snapshot.R'));options(warn=1,readr.num_threads=2)
x<-load_design();p<-x$panel
raw_path<-path(paste0('data_raw/LODES/OD_related/lodes7_tract_agg_2010_2019/lodes_',side,'_outcomes_tract2010_2010_2019.parquet'))
a<-read_parquet(raw_path);id<-if(side=='rac')'h_tract' else 'w_tract'
a<-a %>% mutate(tract_id=as.numeric(.data[[id]]),year=as.integer(year))
sectors<-sprintf('CNS%02d',1:20)
stopifnot(!anyDuplicated(a[c('tract_id','year')]),all(sectors %in% names(a)))
finite<-a %>% filter(if_all(all_of(c('C000',sectors)),is.finite))
stopifnot(all(as.matrix(finite[,c('C000',sectors)])>=0),max(abs(rowSums(as.matrix(finite[,sectors]))-finite$C000))==0)
p<-left_join(p,a %>% select(tract_id,year,total_jobs=C000,all_of(sectors)),by=c('tract_id','year'))
check<-p %>% summarise(rows=n(),both_observed=sum(is.finite(total_jobs)&is.finite(.data[[paste0(side,'_total')]])),max_total_difference=max(abs(total_jobs-.data[[paste0(side,'_total')]]),na.rm=TRUE),rows_missing_any_sector=sum(!if_all(all_of(sectors),is.finite)))
stopifnot(check$max_total_difference==0)
write_csv(check,file.path(OUT,'source_validation.csv'))
for(y in c('total_jobs',sectors))p[[paste0('log_',y)]]<-log(pmax(p[[y]],1))
# Focal treated baseline summaries. Full-panel baseline means only use available t=G-1.
for(g in c('matched','full')){
 b<-p %>% filter(between(first_pis_year,2011,2019),year==first_pis_year-1)
 if(g=='matched')b<-b %>% semi_join(x$pairs %>% filter(group=='pooled',treated_cohort==1) %>% distinct(tract_id),by='tract_id')
 ss<-map_dfr(sectors,function(y){v<-b[[y]];tibble(sample=g,outcome=y,baseline_tracts=sum(is.finite(v)),baseline_mean=mean(v,na.rm=TRUE),baseline_median=median(v,na.rm=TRUE),baseline_zero_share=mean(v==0,na.rm=TRUE))})
 write_csv(ss,file.path(OUT,paste0('baseline_',g,'.csv')))
}
res<-run_models(p,x$pairs,c('total_jobs','log_total_jobs',sectors,paste0('log_',sectors)),'pooled',file.path(OUT,'estimates'))
# All sectors and their total use common complete rows. The count ATTs must add up.
add<-res$att %>% filter(outcome=='total_jobs'|outcome %in% sectors) %>% group_by(specification) %>% summarise(total_att=estimate[outcome=='total_jobs'],sector_sum=sum(estimate[outcome!='total_jobs']),difference=total_att-sector_sum,.groups='drop')
write_csv(add,file.path(OUT,'sector_additivity.csv'));stopifnot(all(abs(add$difference)<1e-7))
# Exact replication of the current paper's total log outcome.
ref<-read_csv(path('output/robustness_specs/did_tables/robustness_sunab_att_paper.csv'),show_col_types=FALSE) %>% filter(outcome==paste0('log_',side))
map<-c(matched_pair_year='spec_a_psm_pair_fe_county_trajectories',full_county_year='spec_c_no_psm_county_year_fe',matched_year='spec_b_psm_twfe_county_trajectories')
z<-res$att %>% filter(outcome=='log_total_jobs') %>% mutate(paper_specification=unname(map[specification])) %>% left_join(ref %>% select(paper_specification=specification,paper_estimate=estimate,paper_se=std_error,paper_n=observations),by='paper_specification') %>% mutate(estimate_error=estimate-paper_estimate,se_error=std_error-paper_se)
write_csv(z,file.path(OUT,'replication_of_paper_total.csv'));stopifnot(nrow(z)==3,!anyNA(z$paper_estimate),all(abs(z$estimate_error)<1e-7),all(abs(z$se_error)<1e-7),all(z$observations==z$paper_n))
writeLines('COMPLETE',file.path(OUT,'COMPLETE.txt'))
