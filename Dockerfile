FROM r-base:latest

MAINTAINER Walt Wells <info@occ-data.org>

RUN apt-get update && apt-get install -y \
    sudo \
    cron \
    systemd \
    gdebi-core \
    pandoc \
    pandoc-citeproc \
    libcurl4-gnutls-dev \
    libcairo2-dev/unstable \
    libxt-dev \
    libxml2-dev \
    libssl-dev \
    gsl-bin \
    libgsl0-dev

RUN R -e "install.packages(c('shiny', 'shinydashboard', 'shinythemes', 'googleVis', 'dplyr', 'tidyr', 'aws.s3', 'stringr', 'data.table', 'DT'), repos='http://cran.rstudio.com/')"

RUN wget --no-verbose https://s3.amazonaws.com/rstudio-shiny-server-os-build/ubuntu-12.04/x86_64/VERSION -O "version.txt" && \
    VERSION=$(cat version.txt)  && \
    wget --no-verbose "https://s3.amazonaws.com/rstudio-shiny-server-os-build/ubuntu-12.04/x86_64/shiny-server-$VERSION-amd64.deb" -O ss-latest.deb && \
    gdebi -n ss-latest.deb && \
rm -f version.txt ss-latest.deb

COPY App /srv/shiny-server/
COPY Assets/shiny-server.conf /etc/shiny-server/shiny-server.conf

RUN touch /srv/shiny-server/runlog.log
COPY Assets/cron.txt /cron.txt
RUN crontab /cron.txt

WORKDIR /srv/shiny-server

EXPOSE 80

RUN echo "local({options(shiny.port = 80, shiny.host = '0.0.0.0')})" >> /usr/lib/R/etc/Rprofile.site

COPY Assets/multipleScripts.sh /usr/bin/multipleScripts.sh
RUN ["chmod", "+x", "/usr/bin/multipleScripts.sh"]
CMD /usr/bin/multipleScripts.sh
