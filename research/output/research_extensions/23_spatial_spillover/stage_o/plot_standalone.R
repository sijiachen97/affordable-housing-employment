suppressPackageStartupMessages(library(tidyverse))
p<-commandArgs(TRUE)[1]
d<-read_csv(file.path(p,'estimates/event_study.csv'),show_col_types=FALSE)%>%filter(covariance=='spatial_50km',between(event,-5,5))
stopifnot(!anyDuplicated(d[c('radius_km','component','outcome','event')]))
z<-d%>%distinct(radius_km,component,outcome)%>%mutate(event=-1,estimate=0,ci_low=0,ci_high=0)
d<-bind_rows(d,z)%>%mutate(component=factor(component,levels=c('center','surroundings','cumulative'),labels=c('Center','Surroundings','Cumulative')))
labels<-c(rac='Resident-held jobs (level)',log_rac='Resident-held jobs (log)',wac='Workplace jobs (level)',log_wac='Workplace jobs (log)',population='Population (level)',log_population='Population (log)',emp_pop_ratio='Employment-to-population ratio')
for(y in names(labels)){
 a<-d%>%filter(outcome==y)
 if(y=='emp_pop_ratio')a<-a%>%mutate(across(c(estimate,ci_low,ci_high),~.x*100))
 a<-a%>%mutate(panel=factor(paste(radius_km,'km |',component),levels=unlist(lapply(c(3,5,7),function(r)paste(r,'km |',levels(d$component))))))
 q<-ggplot(a,aes(event,estimate))+geom_hline(yintercept=0,color='grey50',linewidth=.4)+geom_vline(xintercept=-1,linetype=2,color='grey60')+geom_errorbar(aes(ymin=ci_low,ymax=ci_high),width=.12,color='#285c89',linewidth=.45)+geom_line(color='#285c89',linewidth=.55)+geom_point(color='#285c89',size=1.6)+facet_wrap(~panel,ncol=3,scales='free_y')+scale_x_continuous(breaks=-5:5)+theme_bw(base_size=12)+theme(panel.grid.minor=element_blank(),strip.background=element_rect(fill='#edf1f5',color=NA),plot.title=element_text(face='bold'),plot.caption=element_text(hjust=0))+labs(title=labels[y],subtitle='Stage O: eligibility + guards; no additional surrounding projects',x='Years relative to center placement',y=if(y=='emp_pop_ratio')'Percentage points' else if(startsWith(y,'log'))'Log points' else if(y=='population')'Persons' else 'Jobs',caption='Sun–Abraham; center and pair × year fixed effects. 50 km spatial HAC; 95% pointwise intervals.\nReference year: −1. Each panel has its own y-axis scale.')
 ggsave(file.path(p,paste0('eventstudy_',y,'.png')),q,width=14,height=10,dpi=160)
}
