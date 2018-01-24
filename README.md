# metering-shinyapp
Suite for managing shinyR application to display Data Commons resource use

## Dashboard Examples

![](/Assets/HomePage.png)
![](/Assets/Logs.png)
![](/Assets/SingleMonth.png)

# Configure Billing Logging and Access

## Tagging Resources

One of the features of this app is to show granular resource use by user-defined tags.   It's a good idea to come up with a set of tag definitions for each data commons.   This application will manage tags for `Organization` and `Environment`.   Consider using one primary tag for most commons services (set as a default as `envtag` in `global.R`).   Then you can use `Organization` tags for buckets or services dedicated to a particular user group to understand their use in context of the larger commons. 

## Tagging - Test

To aid in IDing which resources are appropriately tagged and which should be updated use the `TestSuite/tagtest.R` file.   It will pull in metering data using `App/dataprep.R` and then run the test suite to determine which resources currently in use are not tagged.   

## Setting up Billing and Bucket Logs

Make sure billing logs are setup in full for your resource and create a bucket for AWS to push detailed logs.   AWS has good instructions for this step.  Make sure to select the most granular / detailed output, as the application will parse these to understand use. At minimum, you'll need logs to yield files with `tags-and-resources` in the name and other with `aws-billing-csv` in the name.   

Make sure to activate your tags in the billing console so that they are used by AWS and pushed to the new bucket.  

For any commons data buckets you want to observe, be sure to setup bucket logging.   AWS has good instructions for this step.   Roughly:  

* Create a bucket named `<commonsname>-bucket-logs`
* Make sure S3 Log delivery is enabled.
* For each bucket you want to review, enable server logging and push the results to the above bucket. 

Billing and Bucket logging will start pushing new records a few hours after taking the above steps.   The application will work with very little data, but is designed to review up to 12 months of metering at a time. 

## Create Policy and Cost Explorer IAM user

Setup a new IAM user that will just be used for metering and policy review.   Assign the user a policy that only permits access to the metering and log buckets.  See `/Assets/samplepolicy.json` for an example of a policy that allows access to only the metering and bucket logs.   

Get the s3 keys associated with user and add them to `global.R`.

# Deployment

The containerized application sets off an hourly cron to check logs (`LogScraper.R`) and check metering (`dataprep.R`) that are fed into the shiny server dashboard. 

To review logs or troubleshoot in the running container, run: `docker exec -ti <container-id> /bin/bash`.  

## Configuring global.R Creds

Update the global.R with the key values for the IAM user, billing and log bucket names, generic environment tag to use when cleaning metering, commons name for display in the app, and image url.   You'll inject this into the docker container to run the application.  

## Get VM

Tag "commonsmetering" for org and resource name.   Suggest: t2.medium.   Use an image that has docker installed, or install docker CE.  Open up http `80` and https `443`.  Open ssh to your ip.   SSH to VM and copy your global.R to the VM.   

## Get Container

### Option 1: Pull from Quay Repo

Get container from Quay. 

```
sudo docker pull quay.io/occ_data/costapp
```

Tmux/Screen to multiplex.  Then run the container injecting your own local `global.R` creds in to the application.   

```
sudo docker run --rm -v $(pwd)/global.R:/srv/shiny-server/global.R -p 127.0.0.1:80:80 --name costapp quay.io/occ_data/costapp
```
 
### Option 2:  Build your own container

Clone the repo, make any desired updates, then build.   

```
docker build -t costapp .
```

Run your build:   Insert your `global.R` keys to make it work. 

```
docker run --rm -v $(pwd)/global.R:/srv/shiny-server/global.R -p 127.0.0.1:80:80 --name costapp costapp
```

## Update Route53

Create an `A` record for `cost-explorer.<commons-domainname>.xxx` and point it to your vm.  

## Get an SSL Certificate

Get an SSL Certificate using AWS manager or Let's Encrypt and add to the VM.    Store those path files for use below.  

## NGINX setup

For this to work, you need the server in DNS first.

Please keep in mind, this is ONE way of may to setup SSL with letsencrypt. Feel free to use your own preferred method

* Stop anything running on port 809
* Install nginx
	* `apt-get install nginx`
* Install certbot from https://certbot.eff.org
	* Follow the instructions on their site
* Create the redirect file (see below) for certbot to have enough information to work with
	* create the file in /etc/nginx/sites-available
	* make sure you fill in server_name, and enter your LOCAL IP address in the listen line
	* link the file to /etc/nginx/sites-enabled
	* `ln -s /etc/nginx/sites-available/redirect /etc/nginx/sites-enabled/redirect`
* restart nginx (I'm not sure this is necessary)
* Create certificate with certbot
	* `sudo certbot --nginx`
	* Follow prompts, make sure you give a real email address, since that's where they'll let you know if your cert is expiring and needs to be manually updated
	* Select NO redirect, although if you screw up, don't worry, just remake the one from earlier
* Create the reverse file
	* create the file in /etc/nginx/sites-available
	* make sure you update it to point to your new cert files, and enter in your server_name
	* link the file to /etc/nginx/sites-enabled
	* `ln -s /etc/nginx/sites-available/reverse /etc/nginx/sites-enabled/reverse`
* run /root/add_htpassword_user.sh to create password file
	* see below below to create
* restart nginx
	* `service nginx restart`

### Step One: Make /etc/nginx/sites-avilable/redirect

```
server {
  listen <insert your local ip here>:80 default_server;
  server_name _;
  return 301 https://cost-explorer.<commons-domainname>.xxx;
}
```
### Step Two: Make /etc/nginx/site-available/reverse

```
map $http_upgrade $connection_upgrade {
default upgrade;
  '' close;
  }
  upstream websocket {
    server 127.0.0.1:80;
  }
  server {
    ssl on;
    ssl_certificate <insert path to your own pem file here>;
    ssl_certificate key <insert path to your own certificate's key here>;
    ssl_protocols TLSv1.2;
    ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256';
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_stapling on;
    ssl_stapling_verify on;
    server_tokens off;
    listen 443;
    server_name cost-explorer.<commons-domainname>.xxx;
    location / {
      allow 0.0.0.0/0;
      #deny all;
      auth_basic "Restricted Content";
      auth_basic_user_file /etc/nginx/htpassword;
      proxy_buffering off;
      proxy_pass http://websocket;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection $connection_upgrade;
      proxy_connect_timeout 43200000;
      proxy_read_timeout 43200000;
      tcp_nodelay on;
    }
 }
```

### Step Three: create and run add_htpasswd_user.sh

```
#!/bin/bash
PASSWORD_FILE=/etc/nginx/htpassword
echo enter username to add
read USERNAME
echo -n "${USERNAME}:" >> $PASSWORD_FILE
openssl passwd -apr1 >> $PASSWORD_FILE
```



