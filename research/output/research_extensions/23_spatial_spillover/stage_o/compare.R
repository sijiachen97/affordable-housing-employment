suppressPackageStartupMessages(library(tidyverse))
a<-commandArgs(TRUE);root<-a[1];out<-a[2]
for(fn in c('att_long.csv','event_study.csv','pretrend_tests.csv')){
 old<-read_csv(file.path(root,'stage_n',paste0('combined_',fn)),show_col_types=FALSE)%>%mutate(version='Prior: no scale guards')
 new<-read_csv(file.path(out,'estimates',fn),show_col_types=FALSE)%>%mutate(version='New: population and scale guards')
 write_csv(bind_rows(old,new),file.path(out,paste0('comparison_',fn)))
}
e<-read_csv(file.path(out,'comparison_event_study.csv'),show_col_types=FALSE)
for(y in unique(e$outcome)){
 v<-e%>%filter(outcome==y,covariance=='spatial_50km',between(event,-5,5))
 v<-bind_rows(v,v%>%distinct(version,radius_km,component,outcome)%>%mutate(event=-1,estimate=0,ci_low=0,ci_high=0))%>%mutate(component=factor(component,levels=c('center','surroundings','cumulative')))
 if(y=='emp_pop_ratio')v<-v%>%mutate(across(c(estimate,ci_low,ci_high),~.x*100))
 g<-ggplot(v,aes(event,estimate,color=version,group=version))+geom_hline(yintercept=0,color='grey60')+geom_vline(xintercept=-1,linetype=2,color='grey60')+geom_errorbar(aes(ymin=ci_low,ymax=ci_high),width=.1,position=position_dodge(.15),alpha=.7)+geom_line()+geom_point(size=1,position=position_dodge(.15))+facet_grid(radius_km~component,scales='free_y')+theme_bw(base_size=11)+theme(legend.position='bottom')+scale_x_continuous(breaks=-5:5)+scale_color_manual(values=c('#206b88','#999999'))+labs(title=paste('No surrounding new projects:',y),x='Years relative to center placement',y=if(y=='emp_pop_ratio')'Percentage points' else y,color=NULL,caption='Rows:3,5,7 km. Sun–Abraham; center + pair-year FE; 50 km spatial HAC,95% intervals.')
 ggsave(file.path(out,paste0('comparison_',y,'.png')),g,width=13,height=10,dpi=160)
}
