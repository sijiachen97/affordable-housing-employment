source(file.path(Sys.getenv('LIHTC_REFRESH_OUTPUT'),'engine.R'))
ip<-read_csv(file.path(OUT,'intensity_matched_pairs.csv'),show_col_types=FALSE)
for(fam in list('emp_pop_ratio',c('seer_total_population','log_seer_pop'),c('rac_total','log_rac'),c('wac_total','log_wac')))run(p,ip,fam,c('low_intensity','high_intensity'),paste0('intensity/',fam[1]))
primary<-read_parquet(path('data_panels/primary_rac/2010_2019_panel_with_primary_rac.parquet'))%>%select(tract_id,year,starts_with('primary_rac_'))
stopifnot(!anyDuplicated(primary[c('tract_id','year')]))
p<-left_join(p,primary,by=c('tract_id','year'))%>%mutate(primary_emp_pop_ratio=primary_rac_total/seer_total_population,log_primary_rac=log(pmax(primary_rac_total,1)))
for(k in c('low','mid','high'))p[[paste0('log_primary_rac_',k)]]<-log(pmax(p[[paste0('primary_rac_',k)]],1))
stopifnot(all(p$primary_rac_total<=p$rac_total,na.rm=TRUE))
for(fam in list(c('emp_pop_ratio','primary_emp_pop_ratio'),c('rac_total','primary_rac_total','log_rac','log_primary_rac'),c('log_rac_low','log_primary_rac_low'),c('log_rac_mid','log_primary_rac_mid'),c('log_rac_high','log_primary_rac_high'))){
 run(p,pairs,fam,c('pooled','lower_income','higher_income'),paste0('primary/',fam[1]))
 if(fam[1]%in%c('emp_pop_ratio','rac_total'))run(p,ip,fam,c('low_intensity','high_intensity'),paste0('primary_intensity/',fam[1]))
}
z<-read_parquet(path('output/research_extensions/03_near_far/od_near_far_panel.parquet'))%>%select(-h_tract)
p<-left_join(p,z,by=c('tract_id','year'))%>%mutate(pop=if_else(seer_total_population>0,seer_total_population,NA_real_),rac_per_pop=rac_total/pop,od_per_pop=od_total/pop,rac_od_gap_per_pop=(rac_total-od_total)/pop,same_tract_per_pop=same_tract/pop)
ys<-c('rac_per_pop','od_per_pop','rac_od_gap_per_pop','same_tract_per_pop')
for(r in c(5,10,20)){
 stopifnot(all(abs(p[[paste0('near_',r)]]+p[[paste0('far_',r)]]+p$unknown-p$od_total)<1e-8,na.rm=TRUE),all(p$unknown==0,na.rm=TRUE))
 for(k in c('near','far')){
 p[[paste0(k,'_per_pop_',r)]]<-p[[paste0(k,'_',r)]]/p$pop
 p[[paste0('log_',k,'_jobs_',r)]]<-log(pmax(p[[paste0(k,'_',r)]],1))
 }
 p[[paste0('near_share_',r)]]<-if_else(p$od_total>0,p[[paste0('near_',r)]]/p$od_total,NA_real_)
 ys<-c(ys,paste0(c('near_per_pop_','far_per_pop_','log_near_jobs_','log_far_jobs_','near_share_'),r))
}
# Common rows across both measures and ALL radii, as required in paper.
run(p,pairs,ys,'pooled','near_far')
writeLines('COMPLETE',file.path(OUT,'EXTENSIONS_COMPLETE'))
