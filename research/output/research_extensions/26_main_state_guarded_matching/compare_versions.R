suppressPackageStartupMessages(library(tidyverse))
out<-commandArgs(TRUE)[1];root<-'./output';old<-file.path(root,'robustness_specs/event_study/spec_a_county_trajectory_matching');prior<-file.path(root,'research_extensions/25_main_state_clean_controls')
basecols<-c('group','outcome','estimate','std_error','p_value','observations')
a0<-read_csv(file.path(old,'sunab_att.csv'),show_col_types=FALSE)%>%select(all_of(basecols));cf0<-list()
for(g in unique(a0$group))for(y in unique(a0$outcome)){f<-file.path(old,g,'coefficients',paste0('coef_',y,'.csv'));if(file.exists(f))cf0[[paste(g,y)]]<-read_csv(f,show_col_types=FALSE)%>%mutate(group=g,outcome=y)}
for(folder in c('11_pooled_levels','09_income_levels')){
 d<-read_csv(file.path(root,'research_extensions',folder,'att_levels_and_logs.csv'),show_col_types=FALSE)%>%filter(specification=='matched_pair_year',outcome%in%c('rac_total','wac_total','seer_total_population'))%>%select(all_of(basecols));a0<-bind_rows(a0,d)
 cf0[[folder]]<-read_csv(file.path(root,'research_extensions',folder,'coefficients_levels_and_logs.csv'),show_col_types=FALSE)%>%filter(specification=='matched_pair_year',outcome%in%c('rac_total','wac_total','seer_total_population'))
}
# Paper commuting outcome is in distance levels, not logs.
d<-read_csv(file.path(root,'research_extensions/02_commute_income/att_long.csv'),show_col_types=FALSE)%>%filter(specification=='matched_pair_year',outcome=='avg_road_dist_from_s000')%>%select(all_of(basecols));a0<-bind_rows(a0,d)
cf0[['commute']]<-read_csv(file.path(root,'research_extensions/02_commute_income/event_study_coefficients.csv'),show_col_types=FALSE)%>%filter(specification=='matched_pair_year',outcome=='avg_road_dist_from_s000')
AA<-list(a0%>%mutate(version='Paper: county matching'));CF<-list(bind_rows(cf0)%>%mutate(version='Paper: county matching'))
for(v in c('Prior state: unguarded clean controls','New state: covariate guards')){
 loc<-if(startsWith(v,'Prior'))prior else out
 AA[[v]]<-read_csv(file.path(loc,'sunab_att.csv'),show_col_types=FALSE)%>%select(all_of(basecols))%>%mutate(version=v)
 files<-list.files(loc,pattern='^coef_.*csv$',recursive=TRUE,full.names=TRUE)
 CF[[v]]<-map_dfr(files,~read_csv(.x,show_col_types=FALSE))%>%mutate(version=v)
 if(file.exists(file.path(loc,'commute_level_att.csv')))AA[[paste0(v,'cm')]]<-read_csv(file.path(loc,'commute_level_att.csv'),show_col_types=FALSE)%>%select(all_of(basecols))%>%mutate(version=v)
 if(file.exists(file.path(loc,'commute_level_coefficients.csv')))CF[[paste0(v,'cm')]]<-read_csv(file.path(loc,'commute_level_coefficients.csv'),show_col_types=FALSE)%>%mutate(version=v)
}
att<-bind_rows(AA);stopifnot(!anyDuplicated(att[c('version','group','outcome')]))
write_csv(att,file.path(out,'comparison_att_long.csv'))
cf<-bind_rows(CF)%>%mutate(event=as.numeric(sub('year::','',term)))%>%filter(between(event,-5,5))
cf<-bind_rows(cf,cf%>%distinct(version,group,outcome)%>%mutate(event=-1,estimate=0,std_error=0));write_csv(cf,file.path(out,'comparison_event_study.csv'))
for(y in unique(cf$outcome)){
 d<-cf%>%filter(outcome==y)%>%mutate(group=factor(group,levels=c('pooled','lower_income','higher_income')),version=factor(version,levels=c('Paper: county matching','Prior state: unguarded clean controls','New state: covariate guards')))
 if(y=='emp_pop_ratio')d<-d%>%mutate(across(c(estimate,std_error),~.x*100))
 p<-ggplot(d,aes(event,estimate,color=version,group=version))+geom_hline(yintercept=0,color='grey60')+geom_vline(xintercept=-1,linetype=2,color='grey60')+geom_errorbar(aes(ymin=estimate-1.96*std_error,ymax=estimate+1.96*std_error),width=.08,position=position_dodge(.22),alpha=.65)+geom_line()+geom_point(position=position_dodge(.22),size=1.2)+facet_wrap(~group,nrow=1)+theme_bw(base_size=11)+theme(legend.position='bottom',panel.grid.minor=element_blank())+scale_color_manual(values=c('#777777','#c27c24','#21688b'))+scale_x_continuous(breaks=-5:5)+labs(title=y,x='Years relative to first placement',y=if(y=='emp_pop_ratio')'Percentage points' else if(startsWith(y,'log_'))'Log points' else if(y=='seer_total_population')'Persons' else if(startsWith(y,'avg_road'))'km' else 'Jobs',color=NULL,caption='Sun–Abraham; tract and pair-by-year FE; tract-clustered SE; 95% pointwise intervals.')
 ggsave(file.path(out,paste0('comparison_',y,'.png')),p,width=14,height=5,dpi=160)
}
d2<-cf%>%filter(outcome=='emp_pop_ratio',!startsWith(version,'Prior'))%>%mutate(across(c(estimate,std_error),~.x*100),group=factor(group,levels=c('pooled','lower_income','higher_income')))
p2<-ggplot(d2,aes(event,estimate,color=version,group=version))+geom_hline(yintercept=0,color='grey65')+geom_vline(xintercept=-1,linetype=2,color='grey65')+geom_errorbar(aes(ymin=estimate-1.96*std_error,ymax=estimate+1.96*std_error),width=.1,position=position_dodge(.12))+geom_line()+geom_point(position=position_dodge(.12),size=1.3)+facet_wrap(~group,nrow=1)+theme_bw()+theme(legend.position='bottom')+scale_color_manual(values=c('#21688b','#777777'))+scale_x_continuous(breaks=-5:5)+labs(title='Employment-to-population ratio: paper and new guarded matching',y='Percentage points',x='Years relative to first placement',color=NULL,caption='Separate readable comparison; the full three-version chart is also reported.')
ggsave(file.path(out,'comparison_emp_pop_ratio_paper_new.png'),p2,width=14,height=5,dpi=160)
