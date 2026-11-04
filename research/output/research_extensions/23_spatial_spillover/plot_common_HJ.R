suppressPackageStartupMessages(library(tidyverse))
a<-commandArgs(TRUE);out<-a[1];root<-a[2]
for(fn in c('att_long.csv','event_study.csv','pretrend_tests.csv')){
 d<-read_csv(file.path(out,fn),show_col_types=FALSE)%>%filter(sample%in%c('old_common','new_common'))
 for(st in c('h','j')){
  v<-read_csv(file.path(root,paste0('stage_',st),'estimates',fn),show_col_types=FALSE)%>%filter(sample=='new_full');v$sample<-paste0(st,'_full');d<-bind_rows(d,v)
 }
 write_csv(d,file.path(out,fn))
}
e<-read_csv(file.path(out,'event_study.csv'),show_col_types=FALSE)
labels<-c(rac='Resident-held jobs (level)',wac='Workplace jobs (level)',population='Population (level)',log_rac='Resident-held jobs (log)',log_wac='Workplace jobs (log)',log_population='Population (log)',emp_pop_ratio='Employment-to-population ratio')
for(y in names(labels)){
 v<-e%>%filter(sample!='j_full',outcome==y,covariance=='spatial_50km',between(event,-5,5))
 refs<-v%>%distinct(sample,radius_km,component)%>%mutate(event=-1,estimate=0,ci_low=0,ci_high=0)
 v<-bind_rows(v,refs)%>%mutate(version=factor(sample,levels=c('h_full','old_common','new_common'),labels=c('H: full sample','Common treated: H controls','Common treated: J controls')),component=factor(component,levels=c('center','surroundings','cumulative')))
 fac<-if(y=='emp_pop_ratio')100 else 1;v<-v%>%mutate(across(c(estimate,ci_low,ci_high),~.x*fac))
 p<-ggplot(v,aes(event,estimate,color=version,group=version))+geom_hline(yintercept=0,color='grey60')+geom_vline(xintercept=-1,linetype=2,color='grey65')+geom_errorbar(aes(ymin=ci_low,ymax=ci_high),width=.08,position=position_dodge(.2),alpha=.65)+geom_line()+geom_point(size=1.2,position=position_dodge(.2))+facet_grid(radius_km~component)+scale_color_manual(values=c('#999999','#CC7722','#24618B'))+scale_x_continuous(breaks=-5:5)+theme_bw(base_size=11)+theme(legend.position='bottom',panel.grid.minor=element_blank())+labs(title=labels[[y]],subtitle='H/J common treated centers by radius; rows: 3, 5, 10 km',x='Years relative to center placement',y=if(y=='emp_pop_ratio')'Percentage points' else if(grepl('log',y))'Log points' else 'Jobs / persons',color=NULL,caption='Grey to orange: sample composition. Orange to blue: controls change with identical treated centers.\nSun–Abraham; 95% pointwise intervals, spatial HAC 50 km. Contrasts are descriptive, not tests of differences.')
 ggsave(file.path(out,paste0('comparison_',y,'.png')),p,width=13,height=9,dpi=160)
}
# Exact descriptive point-estimate decomposition; not a variance decomposition.
for(fn in c('att_long.csv','event_study.csv')){
 d<-read_csv(file.path(out,fn),show_col_types=FALSE)%>%filter(covariance=='spatial_50km')
 keys<-c('radius_km','component','outcome',if(fn=='event_study.csv')'event')
 w<-d%>%select(all_of(keys),sample,estimate)%>%pivot_wider(names_from=sample,values_from=estimate)%>%mutate(H_selection=old_common-h_full,control_change=new_common-old_common,J_composition=j_full-new_common,total_change=j_full-h_full,error=total_change-H_selection-control_change-J_composition)
 stopifnot(max(abs(w$error),na.rm=TRUE)<1e-8)
 write_csv(w,file.path(out,paste0('decomposition_',fn)))
}
