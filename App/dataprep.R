# Get and clean log .zips.   Create .rds file of available to review. 

if (!require('aws.s3')) install.packages('aws.s3', repos='http://cran.us.r-project.org')
if (!require('dplyr')) install.packages('dplyr', repos='http://cran.us.r-project.org')
if (!require('data.table')) install.packages('data.table', repos='http://cran.us.r-project.org')
if (!require('stringr')) install.packages('stringr', repos='http://cran.us.r-project.org')

source('global.R')

CleanTags <- function(Data, tagvar){
    # Creates DF with "Tag" column based on inputs elsewhere
    #
    # Args: 
    #   Data:   df
    #   tagvar:  environment tag set in global.R;  some missing tags are replaced with this
    # 
    # Returns:
    #   dataframe with prepared tag column 
    test <- Data
    test$tag <- as.character(test$user.Organization)
    if("user.Environment" %in% colnames(test))
        setDT(test)[tag=="", tag:= user.Environment]
    if("user.Name" %in% colnames(test))
        setDT(test)[tag=="", tag:= user.Name]
    
    # Update tags for resources we don't have tags for/don't control
    test$tag <- ifelse(
        test$tag == "", 
        ifelse(grepl("Simple|CloudWatch|Route 53|Key Management|Relational Database", test$ProductName), tagvar, ""), 
        test$tag)
    
    test$tag <- ifelse(
        test$tag == "", 
        ifelse(grepl("EBS|DataTransfer|ElasticIP|NatGateway", test$UsageType), tagvar, ""), 
        test$tag)
    
    test$tag <- ifelse(
        test$tag == "", 
        ifelse(grepl(tagvar, test$ResourceId), tagvar, ""), 
        test$tag)
    
    test$tag <- ifelse(
        test$tag == "", 
        ifelse(grepl("LoadBalancing|PublicIP", test$Operation), tagvar, ""), 
        test$tag)
    
    # clean out common overlap cases
    test$tag <- ifelse(grepl("kube|Kube", test$tag), "Kubernetes", test$tag)
    test$tag <- ifelse(grepl(tagvar, test$tag), tagvar, test$tag)
    test$tag <- ifelse(grepl(substr(envtag, 1, 3), test$tag), tagvar, test$tag)
    
    # remove "Amazon or AWS" in Product Name
    test$ProductName <- gsub("Amazon|AWS", "", test$ProductName) 
    test$ProductName <- gsub("RDS", "Relational Database", test$ProductName)
    
    #strip out punctionation
    test$tag <- gsub("[[:punct:]]", "", test$tag)
    test$tag <- tolower(test$tag)
    
    ## Other Cleaning
    test$UsageStartDate <- as.POSIXct(test$UsageStartDate, format = "%Y-%m-%d %H:%M:%S")  
    test$UsageEndDate <- as.POSIXct(test$UsageEndDate, format = "%Y-%m-%d %H:%M:%S")
    test$ResourceId <- as.character(test$ResourceId)
    
    test
}

GetMetering <- function(access_key, secret_key, bucket, envtag) {
    # gets most detailed 'resources-and-tags' metering from AWS bucket 
    #
    # Args: 
    #   access_key: user's aws access key
    #   secret_key: user's aws secret key
    #   bucket:  s3 bucket where metering is pushed in AWS
    #   envtag:  environment tag set in global.R;  some missing tags are replaced with this
    # 
    # Returns:
    #   list of r data frames of csv contents
    
    Sys.setenv("AWS_ACCESS_KEY_ID" = access_key,
               "AWS_SECRET_ACCESS_KEY" = secret_key) 
    
    objlist <- lapply(get_bucket(bucket), '[[', 1)
    tagged_obj_list <- grep('resources-and-tags', objlist, value=T)
    tagged_obj_list <- head(rev(tagged_obj_list), 12) #last 12 months, most recent first
    
    data_list <- c()
    for (object in tagged_obj_list) {
        location <- paste0('s3://', bucket, '/', object)
        zipped <- save_object(location, file = object)
        file <- sub(".zip", "", object)
        f <- unz(object, file)
        data <- read.csv(f)
        
        # clean up data, tags
        data <- CleanTags(data, envtag)
        
        object_name <- str_extract(object, "\\d{4}-\\d{2}")
        file.remove(object) 
        data_list[[object_name]] <- data
    }
    
    removeNA <- function(df) {
        df <- df[!is.na(df$Rate), ]
    }
    
    newList <- lapply(data_list, removeNA)
    
    #get csv summary to pull last month's storage use
    summary_obj <- tail(grep('aws-billing-csv', objlist, value=T), 2)[1]
    summary_location <- paste0('s3://', bucket, '/', summary_obj)
    file <- save_object(summary_location, file = summary_obj)
    data <- read.csv(file)
    file.remove(summary_obj) 
    
    storage <- data %>%
        filter(ProductName == "Amazon Simple Storage Service", 
               UsageType == "TimedStorage-ByteHrs") %>%
        select(UsageQuantity)
    storage <- round(storage[[1]] / 1024, 2)
    
    
    returnObjects <- list(DataList = newList, StorageUsed = storage)
    returnObjects
}

SummarizeCosts <- function(data, full=FALSE) {
    # quick summary of dataframe by aws productname
    #
    # Args: 
    #   data:  data frame representing csv pulled from AWS
    #   full:  show more granular data with resource IDs, time start/stop, etc
    # 
    # Returns:
    #   r summary data frame
    
    if (full) {
        grouped <- data
        
        grouped$ResourceId <- ifelse(
            grouped$ResourceId == "", "unknown", grouped$ResourceId)
        
        grouped <- grouped %>%
            group_by(ResourceId) %>%
            mutate(UsageStartDate = min(UsageStartDate),  
                   UsageEndDate = max(UsageEndDate), 
                   SumCost = sum(Cost)) %>%
            distinct(ResourceId, .keep_all=TRUE) %>%
            select(ResourceId, ProductName, UsageType, UsageStartDate, 
                   UsageEndDate, tag, SumCost) 
        
        grouped$Display <- paste0(grouped$ProductName, 
                                  ", Cost: $", 
                                  round(grouped$SumCost, 2), 
                                  ", UsageType: ", 
                                  grouped$UsageType,
                                  ", ResourceId: ",
                                  grouped$ResourceId)
        
        grouped <- grouped[grouped$SumCost > 0, ]        
    } else {
        grouped <- data %>%
            group_by(ProductName, tag) %>% #, UsageType) %>%
            summarise(SumCost = round(sum(Cost), 2)) 
        
        grouped <- grouped[grouped$SumCost > 0, ]
        grouped$tag[grouped$tag==""] <- "unknown"
    }
    
    grouped
}

ActiveVMs <- function(datalist) {
    # quick summary of dataframe by aws productname
    #
    # Args: 
    #   datalist:  list of logs gathered by GetMetering Function
    #
    # Returns:
    #   r summary data frame showing tags and active VM flavors
    
    df <- DataList[[1]]
    df$UsageStartDate <- as.Date(df$UsageStartDate)
    today <- tail(unique(df$UsageStartDate), 1)
    
    df <- df %>%
        filter(UsageStartDate == today,
               ProductName == " Elastic Compute Cloud",
               AvailabilityZone != "") %>%
        mutate(Flavor = str_replace(UsageType, ".*:", "")) %>%
        select(tag, Flavor, ResourceId) %>%
        group_by(ResourceId, tag, Flavor) %>%
        summarise()
    df
}

####  Pull in data from logs  ####

DataList <- GetMetering(my_key, 
                        my_secret, 
                        billing_bucket, 
                        envtag)

StorageUsed <- DataList$StorageUsed
DataList <- DataList$DataList

## Summarize 

SumDataList <- lapply(DataList, SummarizeCosts)
SumDataListFULL <- lapply(DataList, SummarizeCosts, full=TRUE)

## Get Current VMs

currentVMS <- ActiveVMs(DataList)

## Group for Export

dataObjects <- list(SumDataList = SumDataList, 
                    SumDataListFULL = SumDataListFULL, 
                    currentVMS = currentVMS)

## Save summary data for use in ShinyR
saveRDS(dataObjects, "dataObjects.rds")

## Get time for dashboard "Last Updated"
timevar <- Sys.time()
sysVars <- list(Time = timevar, Storage = StorageUsed)
saveRDS(sysVars, "sysVars.rds")

