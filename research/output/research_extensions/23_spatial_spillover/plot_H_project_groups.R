suppressPackageStartupMessages(library(tidyverse))
out<-commandArgs(TRUE)[1];e<-read_csv(file.path(out,'event_study.csv'),show_col_types=FALSE)
for(y in c('rac','log_rac')){
 v<-e%>%filter(outcome==y,covariance=='spatial_50km',between(event,-5,5));ref<-v%>%distinct(sample,radius_km,component)%>%mutate(event=-1,estimate=0,ci_low=0,ci_high=0)
 v<-bind_rows(v,ref)%>%mutate(group=factor(sample,levels=c('no_projects','with_projects'),labels=c('No surrounding projects','With surrounding projects')),component=factor(component,levels=c('center','surroundings','cumulative')))
 p<-ggplot(v,aes(event,estimate,color=group,group=group))+geom_hline(yintercept=0,color='grey60')+geom_vline(xintercept=-1,linetype=2,color='grey65')+geom_errorbar(aes(ymin=ci_low,ymax=ci_high),position=position_dodge(.15),width=.08,alpha=.65)+geom_line()+geom_point(position=position_dodge(.15),size=1.4)+facet_grid(radius_km~component)+scale_color_manual(values=c('#24618B','#CC7722'))+scale_x_continuous(breaks=-5:5)+theme_bw(base_size=11)+theme(legend.position='bottom',panel.grid.minor=element_blank())+labs(title=if(y=='rac')'Resident-held jobs: counts' else 'Resident-held jobs: log',subtitle='Original H controls retained; identical cohort weights within each event year; rows 3, 5, 10 km',x='Years relative to center placement',y=if(y=='rac')'Jobs' else 'Log points',color=NULL,caption='Project groups use surrounding TYPE=1 placements during 2010–2019; unknown timing excluded.\nSun–Abraham; 95% pointwise intervals; full-time spatial HAC 50 km.')
 ggsave(file.path(out,paste0('eventstudy_',y,'.png')),p,width=13,height=9,dpi=180)
 p2<-p%+%(v%>%filter(component!='center'))
 ggsave(file.path(out,paste0('eventstudy_surrounding_cumulative_',y,'.png')),p2,width=11,height=9,dpi=180)
}
