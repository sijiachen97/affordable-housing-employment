suppressPackageStartupMessages(library(tidyverse))
out<-dirname(normalizePath(sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])))
root<-'./output/research_extensions'
a<-read_csv(file.path(root,'28_paper_state_guarded_refresh/all_event_study.csv'),show_col_types=FALSE)%>%filter(specification=='matched_pair_year')%>%mutate(event=as.numeric(sub('year::','',term)))%>%filter(between(event,-5,5))
th<-theme_bw(base_size=12)+theme(panel.grid.minor=element_blank(),panel.grid.major.x=element_blank(),panel.grid.major.y=element_line(colour='#e1e7ef',linetype='dotted'),strip.background=element_blank(),strip.text=element_text(face='bold',colour='#214F80'),panel.border=element_rect(colour='#c5cfdc'),legend.position='bottom',legend.title=element_blank())
plot_es<-function(d,file,ylab,columns=1){
 d<-d%>%mutate(group=factor(group,levels=c('pooled','lower_income','higher_income','low_intensity','high_intensity'),labels=c('Pooled','Lower income','Higher income','Lower intensity','Higher intensity')))
 d<-bind_rows(d,distinct(d,group,outcome)%>%mutate(event=-1,estimate=0,std_error=0))
 p<-ggplot(d,aes(event,estimate))+geom_hline(yintercept=0,colour='grey55',linewidth=.4)+geom_vline(xintercept=-1,linetype=2,colour='grey65')+geom_errorbar(aes(ymin=estimate-1.96*std_error,ymax=estimate+1.96*std_error),width=.08,linewidth=.4,colour='#214F80')+geom_line(colour='#214F80',linewidth=.5)+geom_point(colour='#214F80',size=1.5)+facet_wrap(~group,ncol=columns)+scale_x_continuous(breaks=-5:5)+th+labs(x='Years relative to first placement',y=ylab)
 if(columns==1) p<-p+theme(strip.text=element_blank(),strip.background=element_blank())
 for(ext in c('png','pdf'))ggsave(file.path(out,paste0(file,'.',ext)),p,width=if(columns==1)7 else 11,height=3.9,dpi=180)
}
for(g in c('pooled','income'))for(y in c('emp_pop_ratio','log_rac','log_wac','log_seer_pop')){
 d<-a%>%filter(str_starts(analysis,'main/'),outcome==y,if(g=='pooled')group=='pooled' else group%in%c('lower_income','higher_income'))
 if(y=='emp_pop_ratio')d<-d%>%mutate(estimate=100*estimate,std_error=100*std_error)
 plot_es(d,paste0('es_',g,'_',y),if(y=='emp_pop_ratio')'Percentage points' else 'Log points',if(g=='pooled')1 else 2)
}
# Four pooled main outcomes in a fixed reading order; separate scales and explicit units.
d<-a%>%filter(str_starts(analysis,'main/'),group=='pooled',outcome%in%c('emp_pop_ratio','log_rac','log_wac','log_seer_pop'))
stopifnot(!anyDuplicated(d[c('outcome','event')]))
d<-bind_rows(d,distinct(d,outcome)%>%mutate(event=-1,estimate=0,std_error=0))%>%mutate(estimate=estimate*if_else(outcome=='emp_pop_ratio',100,1),std_error=std_error*if_else(outcome=='emp_pop_ratio',100,1),panel=factor(outcome,levels=c('emp_pop_ratio','log_rac','log_wac','log_seer_pop'),labels=c('(a) Employment-to-population ratio (pp)','(b) Log resident-held jobs (total)','(c) Log workplace jobs (total)','(d) Log total population')))
p<-ggplot(d,aes(event,estimate))+geom_hline(yintercept=0,colour='grey55',linewidth=.4)+geom_vline(xintercept=-1,linetype=2,colour='grey65')+geom_errorbar(aes(ymin=estimate-1.96*std_error,ymax=estimate+1.96*std_error),width=.08,linewidth=.4,colour='#214F80')+geom_line(colour='#214F80',linewidth=.5)+geom_point(colour='#214F80',size=1.5)+facet_wrap(~panel,ncol=2,scales='free_y')+scale_x_continuous(breaks=-5:5)+th+theme(panel.spacing.y=grid::unit(.6,'cm'))+labs(x='Years relative to first placement',y='Estimated effect')
for(ext in c('png','pdf'))ggsave(file.path(out,paste0('es_pooled_main_combined.',ext)),p,width=12,height=8,dpi=180)
plot_es(filter(a,analysis=='commute/avg_road_dist_from_s000',group=='pooled'),'es_pooled_commute','km')
d<-filter(a,analysis=='intensity/emp_pop_ratio')%>%mutate(estimate=100*estimate,std_error=100*std_error)
plot_es(d,'es_intensity_emp_pop_ratio','Percentage points',2)
# Retained spatial analysis, no overlays; captions and notes are external.
s<-read_csv(file.path(root,'23_spatial_spillover/stage_o/estimates/event_study.csv'),show_col_types=FALSE)%>%filter(covariance=='spatial_50km',between(event,-5,5))
s<-bind_rows(s,distinct(s,radius_km,component,outcome)%>%mutate(event=-1,estimate=0,ci_low=0,ci_high=0))
for(y in unique(s$outcome)){
 d<-filter(s,outcome==y)%>%mutate(component=factor(component,levels=c('center','surroundings','cumulative'),labels=c('Center','Surroundings','Cumulative')),panel=factor(paste(radius_km,'km |',component),levels=unlist(lapply(c(3,5,7),function(r)paste(r,'km |',c('Center','Surroundings','Cumulative'))))))
 if(y=='emp_pop_ratio')d<-d%>%mutate(across(c(estimate,ci_low,ci_high),~.x*100))
 p<-ggplot(d,aes(event,estimate))+geom_hline(yintercept=0,colour='grey55')+geom_vline(xintercept=-1,linetype=2,colour='grey65')+geom_errorbar(aes(ymin=ci_low,ymax=ci_high),width=.08,linewidth=.4,colour='#214F80')+geom_line(colour='#214F80')+geom_point(colour='#214F80',size=1.4)+facet_wrap(~panel,ncol=3,scales='free_y')+scale_x_continuous(breaks=-5:5)+th+labs(x='Years relative to center placement',y=if(y=='emp_pop_ratio')'Percentage points' else if(startsWith(y,'log'))'Log points' else if(y=='population')'Persons' else 'Jobs')
 for(ext in c('png','pdf'))ggsave(file.path(out,paste0('spatial_',y,'.',ext)),p,width=13,height=9,dpi=170)
}
