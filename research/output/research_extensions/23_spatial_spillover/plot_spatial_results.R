suppressPackageStartupMessages(library(tidyverse))
out<-commandArgs(TRUE)[1]
at<-read_csv(file.path(out,'att_long.csv'),show_col_types=FALSE);es<-read_csv(file.path(out,'event_study.csv'),show_col_types=FALSE)
labels<-c(rac='Resident-held jobs (RAC)',wac='Workplace jobs (WAC)',population='Population',log_rac='Resident-held jobs (log RAC)',log_wac='Workplace jobs (log WAC)',log_population='Population (log)',emp_pop_ratio='Employment-to-population ratio')
for(y in names(labels)){
 v<-es%>%filter(sample=='radius_specific',outcome==y,covariance=='spatial_50km',between(event,-5,5))
 ref<-v%>%distinct(radius_km,component,outcome)%>%mutate(event=-1,estimate=0,ci_low=0,ci_high=0)
 v<-bind_rows(v,ref)%>%mutate(component=factor(component,levels=c('center','surroundings','cumulative'),labels=c('Center tract','Surrounding tracts','Center + surroundings')))
 scale<-if(y=='emp_pop_ratio')100 else 1
 v<-v%>%mutate(across(c(estimate,ci_low,ci_high),~.x*scale))
 fig<-ggplot(v,aes(event,estimate,color=component))+geom_hline(yintercept=0,color='grey55')+geom_vline(xintercept=-1,linetype=2,color='grey65')+geom_errorbar(aes(ymin=ci_low,ymax=ci_high),width=.08)+geom_line()+geom_point(size=1.4)+facet_grid(radius_km~component,scales='fixed')+scale_x_continuous(breaks=-5:5)+scale_color_manual(values=c('#214F80','#CC7722','#338B80'))+theme_bw(base_size=11)+theme(legend.position='none',panel.grid.minor=element_blank(),panel.grid.major=element_line(color='grey92',linetype='dotted'))+labs(title=labels[[y]],subtitle='Matched center and surrounding regions; rows: 3, 5, 10 km',x='Years relative to center first LIHTC placement',y=if(y=='emp_pop_ratio')'Percentage points' else if(grepl('log',y))'Log points' else 'Jobs / persons',caption='Sun-Abraham estimates. Pointwise 95% intervals: full-time spatial HAC, 50 km. Reference: year -1; earliest lead also omitted as in paper.')
 ggsave(file.path(out,paste0('eventstudy_',y,'.png')),fig,width=13,height=9,dpi=180)
}
wide<-at%>%filter(covariance=='spatial_50km')%>%mutate(cell=sprintf('%.4f%s (%.4f)',estimate,case_when(p_value<.01~'***',p_value<.05~'**',p_value<.1~'*',TRUE~''),std_error))%>%select(sample,radius_km,outcome,estimator,component,cell)%>%pivot_wider(names_from=component,values_from=cell)
write_csv(wide,file.path(out,'did_wide.csv'))
