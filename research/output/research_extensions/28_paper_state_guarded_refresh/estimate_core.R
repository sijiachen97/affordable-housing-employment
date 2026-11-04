source(file.path(Sys.getenv('LIHTC_REFRESH_OUTPUT'),'engine.R'))
groups<-c('pooled','lower_income','higher_income')
# Each level/log family shares rows. Other families retain outcome-specific availability.
for(fam in list(c('emp_pop_ratio'),c('seer_total_population','log_seer_pop'),c('rac_total','log_rac'),c('wac_total','log_wac'),c('log_rac_low','log_rac_mid','log_rac_high'),c('log_wac_low','log_wac_mid','log_wac_high'))){run(p,pairs,fam,groups,paste0('main/',fam[1]))}
cm<-read_parquet(path('data_panels/od_commute_panel_residence_road.parquet'))%>%mutate(tract_id=as.numeric(h_tract),year=as.integer(year))%>%select(tract_id,year,starts_with('avg_road_dist_from_'))
p<-left_join(p%>%select(-avg_road_dist_from_s000),cm,by=c('tract_id','year'))
for(y in names(cm)[grepl('avg_road',names(cm))])run(p,pairs,y,if(y=='avg_road_dist_from_s000')groups else 'pooled',paste0('commute/',y))
writeLines('COMPLETE',file.path(OUT,'CORE_COMPLETE'))
