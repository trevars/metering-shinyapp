NoTags <- function(df) {
    # return df showing which resourcesIDs aren't tagged
    #
    # Args: 
    #   data:  data frame resources tagged csv pulled from AWS
    # 
    # Returns:
    #   r summary data frame showing 
    
    noTag <- df[df$tag=='',]

    noTag <- noTag %>% 
        group_by(ResourceId) %>%
        mutate(TotCost = sum(Cost))
    
    ReviewUnique <- noTag[!duplicated(noTag$ResourceId), ]
    ReviewUnique$Cost <- NULL
    ReviewUnique <- ReviewUnique[order(ReviewUnique$TotCost), ]
    
    print(paste0(round((nrow(noTag) / nrow(df)*100), 2), "% of resources without tags"))
    ReviewUnique
}

source("App/dataprep.R")

## Get most recent month to review tags from DataList created in dataprep.R
Data <- DataList[[length(DataList)]]

## Or grab a particular month to review tags that month
# Data <- DataList$`2017-10` 

## now run NoTags to check for issues
MissingTags <- NoTags(Data)

## save csv to to hand review output
write.csv(MissingTags, "missingtags.csv")
