suppressPackageStartupMessages({library(tidyverse);library(fixest);library(arrow)})
setFixest_nthreads(1);options(warn=1)
ROOT<-'.';OUT<-Sys.getenv('LIHTC_REFRESH_OUTPUT');stopifnot(nzchar(OUT));path<-function(...)file.path(ROOT,...)
x<-readRDS(file.path(OUT,'design.rds'));p<-x$panel;pairs<-x$pairs
fit<-function(d,y,fe)feols(as.formula(paste(y,'~ sunab(cohort_sa,year,ref.p=c(-1,.F)) |',fe)),data=d,cluster=~tract_id_num)
run<-function(panel,pairs,ys,groups,tag){
 dest<-file.path(OUT,tag);dir.create(dest,recursive=TRUE,showWarnings=FALSE)
 if(file.exists(file.path(dest,'COMPLETE'))){message('RESUME ',tag);return(invisible(NULL))}
 aa<-cc<-qq<-au<-ids<-list()
 for(g in groups){
 full<-if(g=='pooled')panel else if(g %in% c('lower_income','higher_income'))filter(panel,income_group==g) else filter(panel,is_control|intensity_group==g)
 full<-full%>%filter(if_all(all_of(ys),is.finite))
 pp<-pairs%>%filter(group==g)%>%select(tract_id,match_id,treated_cohort,cohort)
 d<-pp%>%inner_join(full,by='tract_id',relationship='many-to-many')%>%mutate(match_id_num=as.integer(factor(match_id)))
 a<-fit(d,ys[1],'tract_id_num + match_id_num^year');d<-d[fixest::obs(a),]
 a<-fit(full,ys[1],'tract_id_num + county_id^year');full<-full[fixest::obs(a),]
 for(sp in c('matched_pair_year','full_county_year','matched_year')){
 dd<-if(sp=='full_county_year')full else d;fe<-switch(sp,matched_pair_year='tract_id_num + match_id_num^year',full_county_year='tract_id_num + county_id^year',matched_year='tract_id_num + year')
 allfits<-if(startsWith(tag,'industry/'))feols(as.formula(paste('c(',paste(ys,collapse=','),') ~ sunab(cohort_sa,year,ref.p=c(-1,.F)) |',fe)),data=dd,cluster=~tract_id_num) else NULL
 for(y in ys){
 message(tag,' ',g,' ',sp,' ',y,' ',nrow(dd))
 f<-if(is.null(allfits))fit(dd,y,fe) else allfits[[match(y,ys)]];u<-dd[fixest::obs(f),];stopifnot(nrow(u)==nrow(dd),any(u$timing=='never'),!anyNA(u$cohort_sa),all(u$cohort_sa>2010))
 if(sp!='full_county_year')stopifnot(all(u$is_control[u$treated_cohort==0]),all(u$first_pis_year[u$treated_cohort==1]==u$cohort[u$treated_cohort==1]))
 at<-aggregate(f,'ATT');key<-paste(g,sp,y)
 aa[[key]]<-tibble(analysis=tag,group=g,specification=sp,outcome=y,estimate=at[1,1],std_error=at[1,2],p_value=at[1,4],observations=nrow(u))
 ct<-as.data.frame(coeftable(f));names(ct)<-c('estimate','std_error','t_stat','p_value');cc[[key]]<-rownames_to_column(ct,'term')%>%mutate(analysis=tag,group=g,specification=sp,outcome=y)
 wt<-wald(f,keep='year::-[2-5]:',print=FALSE);qq[[key]]<-tibble(analysis=tag,group=g,specification=sp,outcome=y,test='displayed_cohort_specific_leads',p_value=wt$p,df=wt$df1)
 # Save fitted treated IDs; enough to reconstruct sample-matched housing statistics.
 z<-if(sp=='full_county_year')u%>%filter(timing=='treated_2011_2019') else u%>%filter(treated_cohort==1)
 ids[[key]]<-z%>%distinct(tract_id)%>%mutate(analysis=tag,group=g,specification=sp,outcome=y)
 au[[key]]<-tibble(analysis=tag,group=g,specification=sp,outcome=y,observations=nrow(u),unique_tract_years=nrow(distinct(u,tract_id,year)),treated_tracts=n_distinct(z$tract_id),never_tracts=n_distinct(u$tract_id[u$timing=='never']),future_tracts=n_distinct(u$tract_id[u$timing=='future']),pair_count=if(sp=='full_county_year')NA_integer_ else n_distinct(u$match_id))
 }
 }
 }
 write_csv(bind_rows(aa),file.path(dest,'att.csv'));write_csv(bind_rows(cc),file.path(dest,'event_study.csv'));write_csv(bind_rows(qq),file.path(dest,'pretrend.csv'));write_csv(bind_rows(au),file.path(dest,'sample_audit.csv'));write_csv(bind_rows(ids),file.path(dest,'treated_ids.csv'));writeLines('COMPLETE',file.path(dest,'COMPLETE'))
}
