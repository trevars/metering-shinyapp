source('global.R')
if (!require('aws.s3')) install.packages('aws.s3', repos='http://cran.us.r-project.org')
if (!require('stringr')) install.packages('stringr', repos='http://cran.us.r-project.org')
if (!require('dplyr')) install.packages('dplyr', repos='http://cran.us.r-project.org')


bucket <- data_bucket
access_key <- my_key
secret_key <- my_secret


LogScrape <- function(access_key, secret_key, bucket) {
    # gets most detailed 'resources-and-tags' metering from AWS bucket 
    #
    # Args: 
    #   access_key: user's aws access key
    #   secret_key: user's aws secret key
    #   bucket:  s3 bucket where logs live 
    #   n:  debug to shrink list size
    #   
    # Returns:
    #   a list with a single file with aggregated log contents and a 
    #     list of all object names
    
    Sys.setenv("AWS_ACCESS_KEY_ID" = access_key,
               "AWS_SECRET_ACCESS_KEY" = secret_key) 
    
    if (file.exists("LogScrape.rds")) {
        print ("Found Existing Files...")
        
        ## Load prior scrapes
        LS <- readRDS("LogScrape.rds")
        byDay <- LS$byDay
        byIP <- LS$byIP
        byIAM <- LS$byIAM
        
        storedobjlist <- LS$filelist
        newobjlist <- lapply(get_bucket(bucket, max=Inf), '[[', 1)
        newobjlist <- rev(newobjlist)
        
        objlist <- setdiff(newobjlist, storedobjlist)
        storedobjlist <- newobjlist #prep for next run
        
    } else {
        print ("Past Records Did Not Exist - Initializing Log Review")
        
        ## initialize variables
        byDay <- data.frame()
        byIP <- data.frame()
        byIAM <- data.frame() 
        newobjlist <- lapply(get_bucket(bucket, max=Inf), '[[', 1)
        storedobjlist <- objlist <- newobjlist #prep for next run
        
        ## REVERSE AND SET num keep for ease of use
        objlist <- head(rev(objlist), 10000)
    }
    
    counter <- 0
    for (object in objlist) {
        counter <- counter + 1
        location <- paste0('s3://', bucket, '/', object)
        f <- save_object(location, file = object)
        data <- read.table(f, stringsAsFactors = F)
        
        # Clean and Subset
        ## Subset
        data <- data[which(data$V8 == "REST.GET.OBJECT" & data$V11 == 200), ]
        myvars <- names(data) %in% c("V3", "V5", "V6", "V13") 
        data <- data[myvars]
        names(data) <- c("Date", "IP", "IAM", "BytesSent")
        
        ## Clean Date
        data$Day <- str_match(data$Date, '[[0-9]]{2}')
        data$Month <- str_match(data$Date, '[[:alpha:]]{3}')
        data$Month <- match(data$Month, month.abb)
        data$Year <- str_match(data$Date, '[[0-9]]{4}')
        data$Date <- as.Date(paste(data$Month, data$Day, data$Year, sep='.'), "%m.%d.%Y")
        data <- data[, 1:4]
        
        ## Clean IAM
        data$IAM <- gsub("^.*\\/","", data$IAM)
        
        ## Clean Bytes
        data$BytesSent <- as.numeric(data$BytesSent)
        
        # Summarize
        ## Get summary of number of gets and bytes by Day
        df <- data %>%
            group_by(Date) %>%
            summarise(TotalBytes = sum(BytesSent), Count=n())
        byDay <- rbind(byDay, df) # add to existing df, then retally
        byDay <- byDay %>%
            group_by(Date) %>%
            summarise(TotalBytes = sum(TotalBytes), Count=sum(Count))
        byDay <- tail(byDay, 365) #keep most recent year only
        
        ## By IP
        df <- data %>%
            group_by(IP) %>%
            summarise(TotalBytes = sum(BytesSent))
        byIP <- rbind(byIP, df) # add to existing df, then retally
        byIP <- byIP %>%
            group_by(IP) %>%
            summarise(TotalBytes = sum(TotalBytes))
        
        ## By IAM
        df <- data %>%
            group_by(IAM) %>%
            summarise(TotalBytes = sum(BytesSent))
        byIAM <- rbind(byIAM, df) # add to existing df, then retally
        byIAM <- byIAM %>%
            group_by(IAM) %>%
            summarise(TotalBytes = sum(TotalBytes))
        
        print(paste0("Log ", counter, " of ", length(objlist)))
        file.remove(object)
        rm(f)
    }
    
    return(list(filelist=storedobjlist, byDay=byDay, 
                byIP=byIP, byIAM=byIAM))
}

ptm <- proc.time()

LogTallies <- LogScrape(access_key, secret_key, bucket)
saveRDS(LogTallies, "LogScrape.rds")

timetaken <- proc.time() - ptm
print(timetaken)

