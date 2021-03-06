##' Download CRUNCEP data
##' 
##' Download and convert to CF CRUNCEP single grid point from MSTIMIP server using OPENDAP interface
##' @param outfolder
##' @param start_date
##' @param end_date
##' @param lat
##' @param lon
##' @export
##'
##' @author James Simkins, Mike Dietze
download.CRUNCEP <- function(outfolder, start_date, end_date, site_id, lat.in, lon.in, 
                             overwrite = FALSE, verbose = FALSE, ...) {
  
  start_date <- as.POSIXlt(start_date, tz = "UTC")
  end_date <- as.POSIXlt(end_date, tz = "UTC")
  start_year <- lubridate::year(start_date)
  end_year <- lubridate::year(end_date)

  # Check that the start and end date are within bounds
  CRUNCEP_start <- 1901
  CRUNCEP_end <- 2010
  if (start_year < CRUNCEP_start | end_year > CRUNCEP_end) {
    PEcAn.utils::logger.severe(sprintf('Input year range (%d:%d) exceeds the CRUNCEP range (%d:%d)',
                                       start_year, end_year,
                                       CRUNCEP_start, CRUNCEP_end))
  }

  site_id <- as.numeric(site_id)
#  outfolder <- paste0(outfolder, "_site_", paste0(site_id%/%1e+09, "-", site_id %% 1e+09))
  
  lat.in <- as.numeric(lat.in)
  lon.in <- as.numeric(lon.in)
  # Convert lat-lon to grid row and column
  lat_grid <- floor(2 * (90 - lat.in)) + 1
  lon_grid <- floor(2 * (lon.in + 180)) + 1
  dap_base <- "http://thredds.daac.ornl.gov/thredds/dodsC/ornldaac/1220/mstmip_driver_global_hd_climate_"
  
  dir.create(outfolder, showWarnings = FALSE, recursive = TRUE)
  
  ylist <- seq(start_year, end_year, by = 1)
  rows <- length(ylist)
  results <- data.frame(file = character(rows), 
                        host = character(rows), 
                        mimetype = character(rows), 
                        formatname = character(rows), 
                        startdate = character(rows), 
                        enddate = character(rows), 
                        dbfile.name = "CRUNCEP", 
                        stringsAsFactors = FALSE)
  
  var <- data.frame(DAP.name = c("tair", "lwdown", "press", "swdown", "uwind", "vwind", "qair", "rain"), 
                    CF.name = c("air_temperature", "surface_downwelling_longwave_flux_in_air", "air_pressure", 
                                "surface_downwelling_shortwave_flux_in_air", "eastward_wind", "northward_wind", 
                                "specific_humidity", "precipitation_flux"), 
                    units = c("Kelvin", "W/m2", "Pascal", "W/m2", "m/s", "m/s", "g/g", "kg/m2/s"))
  
  for (i in seq_len(rows)) {
    year <- ylist[i]
    ntime <- ifelse(lubridate::leap_year(year), 366 * 4, 365 * 4)

    loc.file <- file.path(outfolder, paste("CRUNCEP", year, "nc", sep = "."))
    PEcAn.utils::logger.info(paste("Downloading",loc.file))
    ## Create dimensions
    lat <- ncdf4::ncdim_def(name = "latitude", units = "degree_north", vals = lat.in, create_dimvar = TRUE)
    lon <- ncdf4::ncdim_def(name = "longitude", units = "degree_east", vals = lon.in, create_dimvar = TRUE)
    time <- ncdf4::ncdim_def(name = "time", units = "sec", vals = (1:ntime) * 21600, 
                      create_dimvar = TRUE, unlim = TRUE)
    dim <- list(lat, lon, time)
    
    var.list <- list()
    dat.list <- list()
    
    ## get data off OpenDAP
    for (j in seq_len(nrow(var))) {
      dap_file <- paste0(dap_base, var$DAP.name[j], "_", year, "_v1.nc4")
      PEcAn.utils::logger.info(dap_file)

      # This throws an error if file not found
      dap <- ncdf4::nc_open(dap_file)

      dat.list[[j]] <- ncdf4::ncvar_get(dap, 
                                 as.character(var$DAP.name[j]), 
                                 c(lon_grid, lat_grid, 1), 
                                 c(1, 1, ntime))
      
      var.list[[j]] <- ncdf4::ncvar_def(name = as.character(var$CF.name[j]), 
                                 units = as.character(var$units[j]), 
                                 dim = dim, 
                                 missval = -999, 
                                 verbose = verbose)
      ncdf4::nc_close(dap)
    }
    ## change units of precip to kg/m2/s instead of 6 hour accumulated precip
    dat.list[[8]] <- dat.list[[8]] / 21600
    
    ## put data in new file
    loc <- ncdf4::nc_create(filename = loc.file, vars = var.list, verbose = verbose)
    for (j in seq_len(nrow(var))) {
      ncdf4::ncvar_put(nc = loc, varid = as.character(var$CF.name[j]), vals = dat.list[[j]])
    }
    ncdf4::nc_close(loc)
    
    results$file[i] <- loc.file
    results$host[i] <- PEcAn.utils::fqdn()
    results$startdate[i] <- paste0(year, "-01-01 00:00:00")
    results$enddate[i] <- paste0(year, "-12-31 23:59:59")
    results$mimetype[i] <- "application/x-netcdf"
    results$formatname[i] <- "CF Meteorology"
  }
  
  return(invisible(results))
} # download.CRUNCEP
