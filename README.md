# metering-shinyapp
Suite for managing shinyR application to display Data Commons resource use

# Why Resource Tagging / Why Cost Explorer App?

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

Make sure billing logs are setup in full for your resource and create a bucket for AWS to push detailed logs.   AWS has good instructions for this step.  Make sure to select the most granular / detailed output, as the application will parse these to understand use.   

Make sure to activate your tags in the billing console so that they are used by AWS and pushed to the new bucket.  

For any commons data buckets you want to observe, be sure to setup bucket logging.   AWS has good instructions for this step.   Roughly:  

* Create a bucket named `<commonsname>-bucket-logs`
* Make sure S3 Log delivery is enabled.
* For each bucket you want to review, enable server logging and push the results to the above bucket. 

Billing and Bucket logging will start pushing new records a few hours after taking the above steps.   The application will work with very little data, but is designed to review up to 12 months of metering at a time. 

## Create Policy and Cost Explorer IAM user

Setup a new IAM user that will just be used for metering and policy review.   Assign the user a policy that only permits access to the metering and log buckets.  See `/Assets/samplepolicy.json` for an example of a policy that allows access to only the metering and bucket logs.   

Get the s3 keys associated with user and add them to `global.R`.

# Setting up App

The containerized application sets off an hourly cron to check logs (`LogScraper.R`) and check metering (`dataprep.R`) that are fed into the shiny server dashboard. 

To review logs or troubleshoot in the running container, run: `docker exec -ti <con bash`.  

## Configuring global.R Creds

Update the global.R with the key values for the IAM user, bucket names, generic environment tag to use when cleaning, commons name, and image url.   You'll inject this into the docker container to run the application.  

## Get VM

Tag "commonsmetering" for org and resource name.   Suggest: t2.medium

Open port 80 to serve traffic...  

## Get Container

### Option 1: Pull from Quay Repo

Get container from Quay. 

```
docker pull quay.io/occ_data/costapp
```

Tmux/Screen to multiplex.  Then run the container injecting your own local `global.R` creds in to the application.   

```
sudo docker run --rm -v $(pwd)/global.R:/srv/shiny-server/global.R -p 80:80 --name costapp quay.io/occ_data/costapp
```
 
### Option 2:  Build your own container

Clone the repo, make any desired updates, then build.   

```
docker build -t costapp .
```

Run your build:   Insert your `global.R` keys to make it work. 

```
docker run --rm -v $(pwd)/global.R:/srv/shiny-server/global.R -p 80:80 --name costapp costapp
```

## Update Route53

Point to VM.  

### Security 

Work with kyle to put inside VPC, nginx password protect behind reverse proxy
Password protecting behind apache/nginx server? 

### Documentation and push

Screenshots, motivation
diagram of application? 
reorg of directory, look for best practices on supporting docker files
discuss test suite in tagging resources

### Kubernetes support

Update and Incorporate .yaml so can be added quickly as commons service.

https://github.com/uc-cdis/shiny-apps/tree/master/nb2/k8s



