if (!require('shiny')) install.packages('shiny', repos='http://cran.us.r-project.org')
if (!require('googleVis')) install.packages('googleVis', repos='http://cran.us.r-project.org')
if (!require('shinythemes')) install.packages('shinythemes', repos='http://cran.us.r-project.org')
if (!require('dplyr')) install.packages('dplyr', repos='http://cran.us.r-project.org')
if (!require('tidyr')) install.packages('tidyr', repos='http://cran.us.r-project.org')
if (!require('DT')) install.packages('DT', repos='http://cran.us.r-project.org')

source('global.R')
source('helper.R')

# load files
sysVars <- reactiveFileReader(10^3, 
                              NULL, 
                              "sysVars.rds", 
                              readRDS)

timevar <- reactive(sysVars()[[1]])
Storage <- reactive(sysVars()[[2]])

dataObjects <- reactiveFileReader(10^3,
                                  NULL,
                                  "dataObjects.rds", 
                                  readRDS)

data <- reactive(dataObjects()[[1]])
dataFULL <- reactive(dataObjects()[[2]])
currentVMS <- reactive(dataObjects()[[3]])

bucketLogs <- reactiveFileReader(10^3,
                                  NULL,
                                  "LogScrape.rds", 
                                  readRDS)

bucketLogs2 <- readRDS("LogScrape.rds")
                           
byDay <- reactive(bucketLogs()[[2]])
byIP <- reactive(bucketLogs()[[3]])
byIAM <- reactive(bucketLogs()[[4]])

# Define UI  ----
ui <- fluidPage(
    theme = shinythemes::shinytheme("sandstone"),
    tags$style(".topimg {
                            margin-left:30px;
                            margin-right:30px;
                            margin-top:25px;
               }"),
    div(class="topimg",img(src=img, width=300, align="right")),
    h1(paste0(commonsName, ' Usage Explorer')),
    h5(textOutput('timestring')),
    sidebarLayout(
        sidebarPanel(
            # Summary
            conditionalPanel(
                'input.dataset === "Current Use"',
                h2("About the Commons Usage Explorer"),
                p("This dashboard allows a commons stakeholder to rapidly 
                  review the useage and resource costs associated with their data commons."),
                h3("About Tags"),
                p("One of the features of this app is to show granular resource use by user-defined tags.   
                  A tag is a commons defined ID that helps show which services, organizations, or groups, 
                  are responsible for which resource use.   Tags are generated when a resource is created.  " ),
                br(),
                p("To learn more visit:"),
                div(HTML("<a href='https://github.com/occ-data/metering-shinyapp'>https://github.com/occ-data/metering-shinyapp</a>"))
            ),
            # Logs
            conditionalPanel(
                'input.dataset === "Logs"',
                h2("Log Queries"),
                p("This tool provides queries of raw data bucket logs.
                  The tables and tools show aggregated results of all 
                  successfull connections to the commons that use the REST.GET.OBJECT
                  protocol."),
                h2("Choose Table Summary"),
                selectInput(inputId = "logdata",
                            label = "Summarize By:",
                            choices = c("byIP", "byIAM"))
            ),
            # Multi Month
            conditionalPanel(
                'input.dataset === "Cost - Multi Month"',
                h2("Cost - Multi Month"),
                p("Review the total monthly cost, grouped by either product type or tag."),
                radioButtons("grouping", "Group By:",
                             choices = list("Product" = 1, "Tag" = 2), 
                             selected = 1, inline = TRUE),
                sliderInput('monthlength', 'Months', 
                            min=1, max=1,
                            value=3, step=1)
            ),
            conditionalPanel(
                'input.dataset === "Cost - Single Month"',
                h2("Cost - Single Month"),
                p("Review the particulars of monthly cost, grouped by either product type or tag.
                  Filter by minimum cost."),
                selectInput('month', 'Month', ""),
                numericInput('costMin', 'Minimum Cost to Display ($)', .01,
                             min = .01, step = .01),
                radioButtons("grouping2", "Group By:",
                             choices = list("Product" = 1, "Tag" = 2), 
                             selected = 1, inline = TRUE)
            ),
            conditionalPanel(
                'input.dataset === "Cost - Tag Review"',
                h2("Cost - Tag Review"),
                p("Review the particulars of monthly cost by tag.  This view helps show the stopping and 
                  starting of resources by tag."),
                selectInput('month3', 'Month', ""),
                selectInput('tag3', 'Select Tag', c("sampval")), 
                actionButton("update", "Update View")
            )
        ),
        
        mainPanel(
            tabsetPanel(
                id = 'dataset',
                tabPanel("Current Use", 
                         br(),
                         h3(textOutput('storagestring')),
                         h3("Currently Active VMs"),
                         htmlOutput("Flavors")),
                tabPanel("Logs", 
                         br(),
                         h3("Raw Data Access Logs"),
                         htmlOutput('Logs'),
                         h3("Total Bytes by Group"),
                         DT::dataTableOutput("logSum")),
                tabPanel("Cost - Multi Month", 
                         br(),
                         htmlOutput('MM'),
                         br(),
                         tableOutput('MMTab')),
                tabPanel("Cost - Single Month", 
                         br(),
                         htmlOutput('SMhead'),
                         htmlOutput('SM'),
                         br(),
                         tableOutput('SMTab')),
                tabPanel("Cost - Tag Review", 
                         br(),
                         htmlOutput('SMFULL'))
                )
            )
        )
)

# Define server logic app ----
server <- function(input, output, session) {
    
    #Set reactive variables
    months <- reactive({
        mydata = data()
        names(mydata)
    })
    nmonths <- reactive({
        mydata = data()
        length(mydata)
    })
    observe({
        updateSliderInput(session, "monthlength",
                          min=1, max = nmonths(),
                          value=3, step=1)
        updateSelectInput(session, "month",
                          choices = months())
        updateSelectInput(session, "month3",
                          choices = months())
        })
    output$timestring <- renderText({
        paste0("Last Updated: ", timevar())
    })
    output$storagestring <- renderText({
        paste0("Raw Storage Currently in Use: ", Storage(), " TiB")
    })

    ## Summary Tab
    ### Current VMs
    output$Flavors <- renderGvis({
        data <- currentVMS() %>% 
            group_by(tag, Flavor) %>% 
            summarize(count=n()) %>%
            spread(tag, count, fill=0)
        flavors <- unique(currentVMS()[3])
        l <- names(data)[-1]
        gvisBarChart(data=data, xvar="Flavor", yvar=l,
                     options=list(
                         isStacked=TRUE,
                         legend='none',
                         orientation='horizontal',
                         hAxes="[{textPosition: 'out'}]"))
        
    })
    
    ## Log Tab
    ### Historical Logs
    output$Logs <- renderGvis({
        gvisLineChart(byDay(), 
                      "Date", 
                      c("TotalBytes","Count"),
                      options=list(
                          series="[{targetAxisIndex: 0},
                                   {targetAxisIndex:1}]",
                          vAxes="[{title:'TotalBytes'}, {title:'Count'}]"
                          ))
    })
    
    datasetInput <- reactive({
        switch(input$logdata,
               "byIP" = byIP(),
               "byIAM" = byIAM())
    })
    
    ### LogTable
    output$logSum = DT::renderDataTable({
        DT::datatable(datasetInput(), options=list(pageLength = 5))
    })
    
    ## Tab 1
    ### Data
    multiMonth <- reactive({
        mM <- data()[1:input$monthlength]
        if(input$grouping == 1) {
                mM <- MultiMonth(mM)
                mM <- Geq.01(mM, 1, row=F)
            } else {
                mM <- MultiMonth(mM, F)
                mM <- Geq.01(mM, 1, row=F)
            }
        return(mM)
    })
    
    multiMonthTab <- reactive({
        mMT <- data()[1:input$monthlength]
        if (input$grouping == 1) {
            mMT <- MultiMonth(mMT, inv=T)
            mMT <- Geq.01(mMT, .1, row=T)
        } else {
            mMT <- MultiMonth(mMT, F, inv=T)
            mMT <- Geq.01(mMT, .1, row=T)
        }
    })
    
    ## Tab2
    ### Plots / Output
    output$MM <- renderGvis({
        l <- names(multiMonth())[-1]
        gvisBarChart(multiMonth(), xvar="Month", yvar=l,
                     options=list(
                         isStacked=TRUE,
                         legend='none',
                         orientation='horizontal',
                         hAxes="[{textPosition: 'out'}]"))
    })
    
    output$MMTab <- renderTable({multiMonthTab()},  
                                 striped = TRUE, 
                                 bordered = TRUE,  
                                 hover = TRUE,  
                                 width = '100%',  
                                 digits = 2, 
                                 na = '0.00', 
                                 spacing = 'xs')
    
    ## Tab 3
    ### Data
    rawT2 <- reactive({
        m <- data()[[input$month]]
        round(sum(m$SumCost), 2)
    })
    
    selectedData1 <- reactive({
        m <- data()[[input$month]]
        m <- m[m$SumCost>=input$costMin,]
        if (input$grouping2 == 1) {
            m <- spread(m, tag, SumCost)
            m <- Geq.01(m, .01)
        } else {
            m <- spread(m, ProductName, SumCost)
            m <- Geq.01(m, .01)
        }
        return(m)
    })
    
    graphvar <- reactive({
        if (input$grouping2 == 1) {
            xvar <- "ProductName"
        } else {
            xvar <- "tag"
        }
        return(xvar)
    })
    
    selectedData1a <- reactive({
        table <- data()[[input$month]]
        table <- table[table$SumCost>=input$costMin,]
        table[order(-table$SumCost),]
    })
    
    ## Tab4 
    ### Plots / Output
    output$SMhead <- renderText({
        paste("<b>Month: </b>", input$month, "<br>",   
              "<b>Monthly Total:</b> $", rawT2())
    })
    
    output$SM <- renderGvis({
        l <- names(selectedData1())[-1]
        gvisBarChart(selectedData1(), 
                     xvar = graphvar(), 
                     yvar = l,
                     options = list(
                         isStacked = TRUE,
                         legend = "none",
                         vAxes = "[{textPosition: 'none', viewWindowMode: 'pretty'}]"
                         ))
    })

    output$SMTab <- renderTable({selectedData1a()},  
                                 striped = TRUE, 
                                 bordered = TRUE,  
                                 hover = TRUE,  
                                 width = '100%',  
                                 digits = 2, 
                                 na = '0.00', 
                                 spacing = 'xs') 
    
    ## Tab 4
    ### Data
    selectedData3 <- eventReactive(
        input$update, {
        m <- dataFULL()[[input$month3]]
        m <- m[m$tag == input$tag3,]
        m }, ignoreNULL = FALSE
    )
    
    observe({
        m <- dataFULL()[[input$month3]]
        available <- unique(m$tag)
        
        updateSelectInput(session, "tag3",
                          label="Select Tag",
                          choices = available,
                          selected = available[1])
    })
    
    ### Plot
    output$SMFULL <- renderGvis({
        gvisTimeline(data=selectedData3(), 
                     rowlabel="UsageType",
                     barlabel="Display",
                     start="UsageStartDate", 
                     end="UsageEndDate",
                     options=list(#timeline="{groupByRowLabel:true}",
                                  height=400))
    })

}

## Run app
shinyApp(ui, server)

