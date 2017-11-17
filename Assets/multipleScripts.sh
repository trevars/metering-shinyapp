#!/bin/bash

/usr/sbin/cron -f -l 8 &
Rscript /srv/shiny-server/dataprep.R && Rscript /srv/shiny-server/LogScraper.R && Rscript /srv/shiny-server/app.R 
exec shiny-server 2>&1
