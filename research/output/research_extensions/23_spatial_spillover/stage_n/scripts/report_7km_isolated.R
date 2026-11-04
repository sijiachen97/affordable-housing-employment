suppressPackageStartupMessages(library(tidyverse))
a<-commandArgs(TRUE);root<-a[1];out<-a[2]
for(fn in c('att_long.csv','event_study.csv','pretrend_tests.csv')){
 old<-read_csv(file.path(root,'stage_l/estimates',fn),show_col_types=FALSE)%>%filter(sample=='new_full',radius_km%in%c(3,5))
 new<-read_csv(file.path(out,'estimates',fn),show_col_types=FALSE)%>%filter(radius_km==7)
 write_csv(bind_rows(old,new),file.path(out,paste0('combined_',fn)))
}
e<-read_csv(file.path(out,'combined_event_study.csv'),show_col_types=FALSE)
for(y in c('rac','log_rac','wac','population','log_wac','log_population','emp_pop_ratio')){
 v<-e%>%filter(outcome==y,covariance=='spatial_50km',between(event,-5,5))
 v<-bind_rows(v,v%>%distinct(sample,radius_km,component,outcome,covariance)%>%mutate(event=-1,estimate=0,ci_low=0,ci_high=0))%>%mutate(component=factor(component,levels=c('center','surroundings','cumulative'),labels=c('Center tract','Surrounding tracts','Center + surroundings')))
 if(y=='emp_pop_ratio')v<-v%>%mutate(across(c(estimate,ci_low,ci_high),~.x*100))
 p<-ggplot(v,aes(event,estimate))+geom_hline(yintercept=0,color='grey65')+geom_vline(xintercept=-1,linetype=2,color='grey65')+geom_errorbar(aes(ymin=ci_low,ymax=ci_high),width=.1,color='#245c7e')+geom_line(color='#245c7e')+geom_point(color='#245c7e',size=1.5)+facet_grid(radius_km~component,scales='free_y')+theme_bw(base_size=12)+labs(title=paste('No additional surrounding projects:',y),subtitle='H matching followed by isolation filter; original matched controls retained',x='Years relative to center placement',y=if(y=='emp_pop_ratio')'Percentage points' else y,caption='Rows: 3, 5, 7 km. Sun–Abraham estimates; 95% pointwise intervals; 50 km spatial HAC.')+scale_x_continuous(breaks=-5:5)
 ggsave(file.path(out,paste0('eventstudy_',y,'.png')),p,width=13,height=9,dpi=160)
}
