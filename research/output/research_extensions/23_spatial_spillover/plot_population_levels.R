suppressPackageStartupMessages(library(tidyverse))
out<-commandArgs(TRUE)[1];a<-read_csv(file.path(out,'att_long.csv'),show_col_types=FALSE);e<-read_csv(file.path(out,'event_study.csv'),show_col_types=FALSE)
root<-commandArgs(TRUE)[2]
for(fn in c('att_long.csv','event_study.csv','pretrend_tests.csv')){
 old<-read_csv(file.path(root,'stage_d',fn),show_col_types=FALSE)%>%filter(sample=='radius_specific')
 if('estimator'%in%names(old))old<-old%>%filter(estimator=='sun_abraham')
 old$sample<-'old_full'
 new<-read_csv(file.path(out,fn),show_col_types=FALSE)%>%filter(sample=='new_full')
 write_csv(bind_rows(old,new),file.path(out,fn))
}
for(fn in c('att_long.csv','event_study.csv','pretrend_tests.csv')){
 prev<-read_csv(file.path(root,'stage_g/estimates',fn),show_col_types=FALSE)%>%filter(sample=='new_full');prev$sample<-'prior_full'
 now<-read_csv(file.path(out,fn),show_col_types=FALSE)%>%filter(sample!='prior_full')
 write_csv(bind_rows(now,prev),file.path(out,fn))
}
a<-read_csv(file.path(out,'att_long.csv'),show_col_types=FALSE);e<-read_csv(file.path(out,'event_study.csv'),show_col_types=FALSE)
labels<-c(rac='Resident-held jobs (RAC)',wac='Workplace jobs (WAC)',population='Population',log_rac='Resident-held jobs (log RAC)',log_wac='Workplace jobs (log WAC)',log_population='Population (log)',emp_pop_ratio='Employment-to-population ratio')
for(kind in 'full')for(y in names(labels)){
 v<-e%>%filter(sample%in%paste0(c('old_','prior_','new_'),kind),outcome==y,covariance=='spatial_50km',between(event,-5,5))
 refs<-v%>%distinct(sample,radius_km,component,outcome)%>%mutate(event=-1,estimate=0,ci_low=0,ci_high=0)
 v<-bind_rows(v,refs)%>%mutate(version=case_when(sample=='old_full'~'Original (D)',sample=='prior_full'~'Earlier log job growth (G)',TRUE~'Population and absolute job growth (H)'),component=factor(component,levels=c('center','surroundings','cumulative'),labels=c('Center tract','Surrounding tracts','Center + surroundings')))
 factor<-if(y=='emp_pop_ratio')100 else 1;v<-v%>%mutate(across(c(estimate,ci_low,ci_high),~.x*factor))
 p<-ggplot(v,aes(event,estimate,color=version,group=version))+geom_hline(yintercept=0,color='grey60')+geom_vline(xintercept=-1,linetype=2,color='grey65')+geom_errorbar(aes(ymin=ci_low,ymax=ci_high),width=.08,position=position_dodge(.14),alpha=.7)+geom_line()+geom_point(size=1.3,position=position_dodge(.14))+facet_grid(radius_km~component)+scale_color_manual(values=c('Original (D)'='#CC7722','Earlier log job growth (G)'='#888888','Population and absolute job growth (H)'='#24618B'))+scale_x_continuous(breaks=-5:5)+theme_bw(base_size=11)+theme(legend.position='bottom',panel.grid.minor=element_blank(),panel.grid.major=element_line(color='grey92',linetype='dotted'))+labs(title=labels[[y]],subtitle='All 2011–2019 cohorts; 2010–2019 panel; rows: 3, 5, 10 km',x='Years relative to center first placement',y=if(y=='emp_pop_ratio')'Percentage points' else if(grepl('log',y))'Log points' else 'Jobs / persons',color=NULL,caption='Sun–Abraham; pointwise 95% intervals, full-time spatial HAC 50 km. H: available pre-period growth constraints; 2011 remains levels only.')
 ggsave(file.path(out,paste0('comparison_',kind,'_',y,'.png')),p,width=13,height=9,dpi=180)
}
wide<-a%>%filter(covariance=='spatial_50km')%>%mutate(cell=sprintf('%.4f%s (%.4f)',estimate,case_when(p_value<.01~'***',p_value<.05~'**',p_value<.1~'*',TRUE~''),std_error))%>%select(sample,radius_km,outcome,component,cell,pairs,observations)%>%pivot_wider(names_from=component,values_from=cell)
write_csv(wide,file.path(out,'att_comparison_wide.csv'))
