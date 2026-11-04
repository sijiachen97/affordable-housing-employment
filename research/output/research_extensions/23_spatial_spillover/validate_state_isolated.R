suppressPackageStartupMessages(library(tidyverse))
a<-commandArgs(TRUE);root<-a[1];out<-a[2];z<-readRDS(file.path(root,'stage_a/neighborhood_cache.rds'));b<-z$base;p<-z$pts
m<-read_csv(file.path(out,'matched_pairs.csv'),show_col_types=FALSE);audit<-read_csv(file.path(out,'propensity_audit.csv'),show_col_types=FALSE)
e<-read_csv(file.path(root,'stage_b/eligibility_and_matching_status.csv'),show_col_types=FALSE)%>%filter(!is.na(clean_control))
stopifnot(!anyDuplicated(m[c('radius_km','core_caliper','cohort','treated_id')]),!anyDuplicated(m[c('radius_km','core_caliper','cohort','control_id')]))
for(r in c(3,5,10)){
 mm<-m%>%filter(radius_km==r);el<-e%>%filter(radius_km==r);stopifnot(identical(el$tract_id,b$tract_id))
 for(i in seq_len(nrow(mm))){v<-mm[i,];ti<-v$treated_index;ci<-v$control_index
  stopifnot(b$tract_id[ti]==v$treated_id,b$tract_id[ci]==v$control_id,b$first_pis_year[ti]==v$cohort,
    is.na(b$first_pis_year[ci])||b$first_pis_year[ci]>2019,el$clean_control[ci],el$treated_complete[ti],
    substr(sprintf('%011.0f',v$treated_id),1,2)==substr(sprintf('%011.0f',v$control_id),1,2),
    length(z$members[[as.character(r)]][[ti]])>1,length(z$members[[as.character(r)]][[ci]])>1,
    length(intersect(z$members[[as.character(r)]][[ti]],z$members[[as.character(r)]][[ci]]))==0,
    v$max_core_distance<=v$core_caliper+1e-12)
 }
}
q<-m%>%left_join(audit,by=c('radius_km','cohort'));stopifnot(all(q$score_distance<=q$ps_caliper+1e-12))
write_csv(m%>%mutate(control_timing=if_else(is.na(b$first_pis_year[control_index]),'never','after_2019'))%>%count(radius_km,core_caliper,control_timing),file.path(out,'control_timing_audit.csv'))
raw<-read_csv('./data_raw/LIHTC/LIHTC_public/LIHTCPUB.csv',col_types=cols(.default=col_character()))%>%filter(str_trim(type)=='1')%>%mutate(tract_id=suppressWarnings(as.numeric(fips2010)),pis=suppressWarnings(as.numeric(yr_pis)),units=suppressWarnings(as.numeric(n_units)))
for(r in c(3,5,10)){
 mm<-m%>%filter(radius_km==r)
 for(k in mm$treated_index){
  neighbors<-setdiff(p$tract_id[z$members[[as.character(r)]][[k]]],b$tract_id[k])
  rr<-raw%>%filter(tract_id%in%neighbors)
  stopifnot(!any(is.na(rr$pis)|rr$pis%in%c(8888,9999)),!any(rr$pis>=2010&rr$pis<=2019))
 }
}
writeLines('PASS: independently checked raw TYPE=1 records: matched treated surroundings have no known 2010-2019 placements or unknown timing; center excluded from screen.',file.path(out,'ISOLATION_VALIDATION.txt'))
h<-list()
for(i in seq_len(nrow(m))){v<-m[i,];ids<-p$tract_id[z$members[[as.character(v$radius_km)]][[v$treated_index]]]
 for(period in c('first_year','through_2019')){end<-if(period=='first_year')v$cohort else 2019
  rr<-raw%>%filter(tract_id%in%ids,pis>=v$cohort,pis<=end)
  h[[length(h)+1]]<-tibble(radius_km=v$radius_km,core_caliper=v$core_caliper,cohort=v$cohort,treated_id=v$treated_id,period=period,projects=nrow(rr),units_observed=sum(rr$units[is.finite(rr$units)&rr$units>=0]),missing_units=sum(!is.finite(rr$units)|rr$units<0))
 }
}
h<-bind_rows(h);write_csv(h,file.path(out,'housing_scale_by_center.csv'))
write_csv(h%>%group_by(radius_km,core_caliper,period)%>%summarise(treated=n(),mean_projects=mean(projects),median_projects=median(projects),complete_units=sum(missing_units==0),mean_units=mean(units_observed[missing_units==0]),median_units=median(units_observed[missing_units==0]),.groups='drop'),file.path(out,'housing_scale_summary.csv'))
bal<-read_csv(file.path(out,'balance_by_cohort.csv'),show_col_types=FALSE)
gg<-bal%>%filter(is_core,core_caliper==1)%>%ggplot(aes(factor(cohort),covariate,fill=abs(smd_after)))+geom_tile()+geom_text(aes(label=sprintf('%.2f',abs(smd_after))),size=2.4)+facet_wrap(~radius_km,ncol=1)+scale_fill_gradient(low='white',high='#BC5343',limits=c(0,.3))+theme_minimal(base_size=10)+labs(x='Treated cohort',y=NULL,fill='Absolute SMD',title='Center and surrounding area: pre-treatment balance',subtitle='Same-state matching; core pairwise caliper = 1 treated SD')
ggsave(file.path(out,'core_balance_by_cohort.png'),gg,width=10,height=12,dpi=160)
writeLines('PASS: independently checked matched IDs, treatment dates, never/future controls, clean-control flags, exact same-state and non-overlap restrictions, nonempty surrounding areas, no within-cohort control reuse, and recorded caliper bounds.',file.path(out,'INDEPENDENT_VALIDATION.txt'))
