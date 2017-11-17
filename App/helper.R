
# Commonly used helper functions across suite. 

## For Multi Month Plots
gB <- function(data, product=TRUE) {
    # summarises an individual month
    #
    # Args: 
    #   data:  individual DF from SumDataList prepared in dataprep.R
    #   product:  group by product,  if F, group_by tag
    # 
    # Returns:
    #   dataframe with summarizes for month
    month <- names(data)
    df <- data[[month]]
    if (product==TRUE) {
        df <- df %>%
            group_by(ProductName) %>%
            summarise(SumCost = round(sum(SumCost), 2))
        df$Month <- month
        df$ProductName <- as.character(df$ProductName)
    } else {
        df <- df %>%
            group_by(tag) %>%
            summarise(SumCost = round(sum(SumCost), 2))
        df$Month <- month
        df$tag <- as.character(df$tag)        
    }
    return(data.frame(df))
}

MultiMonth <- function(DL, product=TRUE, inv=FALSE) {
    # calls gB across entire list, cleans so single longform DF returned
    #
    # Args: 
    #   DL:  months in SumDataList requested by user in app
    #   product:  for use with gB function (see above)
    #   inv:  create wide by month or product cost
    # 
    # Returns:
    #   dataframe with summarizes for every month in requested list
    new <- data.frame()
    for (i in 1:length(DL)) {
        d <- DL[i]
        temp <- gB(d, product)
        new <- rbind(new, temp)
    }
    if (product) {
        if (inv) {
            new <- spread(new, Month, SumCost)
        } else {
            new <- spread(new, ProductName, SumCost)
        }
    }  else  {
        if (inv) {
            new <- spread(new, Month, SumCost)
        } else {
            new <- spread(new, tag, SumCost)
        }
    }
    return(new)
}

Geq.01 <- function(df, val, row=T) {
    # takes a DF and removes rows/cols where the sums are >= val
    #
    # Args: 
    #   df:  data frame (wideform)
    #   val:  row or col sums must be >= this value to remain
    # 
    # Returns:
    #   subsetted dataframe based on value
    if (row) {
        df <- df[rowSums(df[2:ncol(df)], na.rm=T) > val,]
    } else{
        df <- df[,c(TRUE, colSums(df[2:ncol(df)], na.rm=T) > val)]
    }
    return(df)
}