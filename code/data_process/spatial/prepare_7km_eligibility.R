# Stage B: exploratory matching and balance; no causal estimates.
# All predictors are measured by g-1. Outcomes and manuscript are unchanged.
suppressPackageStartupMessages({library(tidyverse);library(Matrix);library(sf)})
a <- commandArgs(TRUE); src <- a[1]; out <- a[2]
metric <- if(length(a)>=3)a[3] else 'propensity'
stopifnot(metric %in% c('propensity','mahalanobis'))
dir.create(out,recursive=TRUE,showWarnings=FALSE)
root <- '.'
z <- readRDS(file.path(src,'neighborhood_cache.rds')); b <- z$base; pts <- z$pts
idx <- match(b$tract_id,pts$tract_id); state <- substr(sprintf('%011.0f',b$tract_id),1,2)
coverage <- read_csv(file.path(src,'center_geography_coverage.csv.gz'),show_col_types=FALSE)
vars <- c('rac_total','wac_total','seer_total_population','seer_nh_black','seer_nh_aian','seer_nh_api','seer_hispanic','seer_age_under_29','seer_age_55_plus','rac_earn_le_1250','rac_earn_ge_3333','wac_earn_le_1250','wac_earn_ge_3333')
p <- read_csv(file.path(root,'data_panels/2010_2019_did_panel_with_seer.csv'),show_col_types=FALSE,col_select=all_of(c('tract_id','year',vars)))
stopifnot(!anyDuplicated(p[c('tract_id','year')]))
# Include coordinates from projects lacking valid tract IDs. Centroid exposure
# remains an additional conservative screen, not a substitute for coordinates.
raw <- read_csv(file.path(root,'data_raw/LIHTC/LIHTC_public/LIHTCPUB.csv'),col_types=cols(.default=col_character())) %>%
 filter(str_trim(type)=='1') %>% mutate(tract_id=suppressWarnings(as.numeric(fips2010)),pis=suppressWarnings(as.numeric(yr_pis)),
 lat=suppressWarnings(as.numeric(latitude)),lon=suppressWarnings(as.numeric(longitude)),units=suppressWarnings(as.numeric(n_units)),
 known=!is.na(pis)&!pis%in%c(8888,9999),validxy=is.finite(lat)&is.finite(lon)&abs(lat)<=90&abs(lon)<=180&!(lat==0&lon==0))
write_csv(raw %>% count(known,validxy),file.path(out,'project_location_audit.csv'))
rp <- raw %>% filter(validxy, !known | between(pis,2010,2019))
message('Checking actual project coordinates')
geo <- st_as_sf(pts[idx,],coords=c('centroid_lon','centroid_lat'),crs=4326)
gp <- st_as_sf(rp,coords=c('lon','lat'),crs=4326)
near <- st_is_within_distance(geo,gp,dist=10010)
hav <- function(la,lo,lat,lon) { q<-pi/180;2*6371.0088*asin(pmin(1,sqrt(sin((lat-la)*q/2)^2+cos(la*q)*cos(lat*q)*sin((lon-lo)*q/2)^2))) }

eligibility<-list()
annual <- lapply(2010:2019,function(yr){v<-p %>% filter(year==yr);as.matrix(v[match(pts$tract_id,v$tract_id),vars])})
for(rad in 7) {
 message('Building region predictors: ',rad,' km')
 mem<-z$members[[as.character(rad)]]; cv<-coverage %>% filter(radius_km==rad)
 stopifnot(identical(cv$tract_id,b$tract_id))
 A<-sparseMatrix(i=rep(seq_len(nrow(b)),lengths(mem)),j=unlist(mem),x=1,dims=c(nrow(b),nrow(pts)))
 sums<-lapply(annual,function(m){missing<-!is.finite(m); m[missing]<-0; s<-as.matrix(A%*%m);s[as.matrix(A%*%missing)>0]<-NA_real_;s})
 exact_exposed<-vapply(seq_len(nrow(b)),function(k){j<-near[[k]];any(hav(pts$centroid_lat[idx[k]],pts$centroid_lon[idx[k]],rp$lat[j],rp$lon[j])<=rad)},logical(1))
 centroid_exposed<-vapply(z$events[[as.character(rad)]],function(v)any(v>=2010&v<=2019),logical(1))
 clean<- (is.na(b$first_pis_year)|b$first_pis_year>2019)&cv$incomplete_outcome_tracts==0&cv$unknown_timing_tracts==0&!centroid_exposed&!exact_exposed
 # Treated neighbors may have additional projects, including prior projects.
 # Unknown neighboring timing is flagged, not used to drop treated centers.
 eligibility[[as.character(rad)]]<-tibble(radius_km=rad,tract_id=b$tract_id,treated_complete=cv$incomplete_outcome_tracts==0,
   unknown_timing_neighbors=cv$unknown_timing_tracts,clean_control=clean,actual_coordinate_exposure=exact_exposed)
 saveRDS(sums,file.path(out,paste0("region_annual_sums_",rad,"km.rds")))
}
write_csv(bind_rows(eligibility),file.path(out,"eligibility_and_matching_status.csv"))
