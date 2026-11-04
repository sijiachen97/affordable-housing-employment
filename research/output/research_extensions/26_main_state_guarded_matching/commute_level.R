suppressPackageStartupMessages({library(tidyverse);library(fixest);library(arrow)})
out<-commandArgs(TRUE)[1];pairs<-read_csv(file.path(out,'matched_pairs.csv'),show_col_types=FALSE)
p<-read_parquet('./data_panels/od_commute_panel_residence_road.parquet')%>%transmute(tract_id=as.numeric(h_tract),year=as.integer(year),avg_road_dist_from_s000)%>%filter(between(year,2010,2019))
A<-C<-list()
for(g in unique(pairs$group)){
 d<-pairs%>%filter(group==g)%>%inner_join(p,by='tract_id',relationship='many-to-many')%>%mutate(cohort_sa=if_else(is.na(first_pis_year),9999,first_pis_year),match_id_num=as.integer(factor(match_id)))
 f<-feols(avg_road_dist_from_s000~sunab(cohort_sa,year,ref.p=c(-1,.F))|tract_id_num+match_id_num^year,data=d,cluster=~tract_id_num)
 a<-aggregate(f,'ATT');A[[g]]<-tibble(group=g,outcome='avg_road_dist_from_s000',estimate=a[1,1],std_error=a[1,2],p_value=a[1,4],observations=nobs(f))
 C[[g]]<-as.data.frame(coeftable(f))%>%rownames_to_column('term')%>%rename(estimate=Estimate,std_error=`Std. Error`)%>%mutate(group=g,outcome='avg_road_dist_from_s000')
}
write_csv(bind_rows(A),file.path(out,'commute_level_att.csv'));write_csv(bind_rows(C),file.path(out,'commute_level_coefficients.csv'))
