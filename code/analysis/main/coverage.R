source('code/analysis/main/engine.R')
z<-read_parquet(path('output/research_extensions/03_near_far/od_near_far_panel.parquet'))%>%select(tract_id,year,od_total,unknown,road_coverage)
d<-pairs%>%filter(group=='pooled')%>%select(tract_id,match_id)%>%inner_join(p,by='tract_id',relationship='many-to-many')%>%left_join(z,by=c('tract_id','year'))%>%filter(is.finite(od_total),od_total>0,is.finite(rac_total),is.finite(seer_total_population),seer_total_population>0)%>%mutate(match_id_num=as.integer(factor(match_id)))
f<-fit(d,'emp_pop_ratio','tract_id_num + match_id_num^year');d<-d[fixest::obs(f),]
write_csv(tibble(observations=nrow(d),od_jobs=sum(d$od_total),rac_jobs=sum(d$rac_total),od_to_rac=sum(d$od_total)/sum(d$rac_total),mean_tract_year_coverage=mean(d$od_total/d$rac_total,na.rm=TRUE),unknown_distance_jobs=sum(d$unknown),mean_road_coverage=mean(d$road_coverage,na.rm=TRUE)),file.path(OUT,'descriptives/od_coverage.csv'))
