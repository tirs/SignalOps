# SignalOps Demo Data Seed Script (MySQL)
# Generates realistic synthetic data for demonstration

library(DBI)
library(RMariaDB)
library(dplyr)
library(lubridate)
library(jsonlite)
library(uuid)

# Configuration
config <- list(
  host = Sys.getenv("DB_HOST", "srv1539.hstgr.io"),
  port = as.integer(Sys.getenv("DB_PORT", "3306")),
  dbname = Sys.getenv("DB_NAME", "u280406916_SignalOps"),
  user = Sys.getenv("DB_USER", "u280406916_SignalOps"),
  password = Sys.getenv("DB_PASSWORD", "6GSaZLVVPMi>")
)

# Connect to database
cat("Connecting to database...\n")
cat(sprintf("  Host: %s\n", config$host))
cat(sprintf("  Database: %s\n", config$dbname))

conn <- dbConnect(
  RMariaDB::MariaDB(),
  host = config$host,
  port = config$port,
  dbname = config$dbname,
  username = config$user,
  password = config$password
)

cat("Connected successfully!\n\n")

# Seed parameters
TENANT_ID <- "00000000-0000-0000-0000-000000000001"
START_DATE <- Sys.Date() - 180  # 6 months of data
END_DATE <- Sys.Date()
TEAMS <- c("Sales", "Marketing", "Engineering", "Support", "Finance")
REGIONS <- c("North America", "Europe", "Asia Pacific", "Latin America")
CHANNELS <- c("Web", "Mobile", "API", "Partner")
PRODUCTS <- c("Pro", "Enterprise", "Starter", "Custom")
METRICS <- c(
  "revenue", "users_active", "page_views", "conversion_rate",
  "support_tickets", "response_time_ms", "error_rate", "api_calls"
)

# Helper function to generate seasonal pattern
generate_seasonal_value <- function(date, base_value, variance = 0.2) {
  # Day of week effect
  dow <- wday(date)
  dow_effect <- ifelse(dow == 1, 0.7, ifelse(dow == 7, 0.8, 1.0))
  
  # Monthly seasonality
  month_effect <- 1 + 0.1 * sin(2 * pi * month(date) / 12)
  
  # Random noise
  noise <- rnorm(1, 1, variance)
  
  base_value * dow_effect * month_effect * noise
}

# Generate metrics data
cat("Generating metrics data...\n")
dates <- seq(START_DATE, END_DATE, by = "day")

# Process in smaller batches
batch_size <- 7  # Process 7 days at a time
total_inserted <- 0

for (batch_start in seq(1, length(dates), by = batch_size)) {
  batch_end <- min(batch_start + batch_size - 1, length(dates))
  batch_dates <- dates[batch_start:batch_end]
  
  metrics_data <- data.frame()
  
  for (date in batch_dates) {
    date <- as.Date(date, origin = "1970-01-01")
    
    # Sample fewer combinations for faster seeding
    sampled_teams <- sample(TEAMS, 3)
    sampled_regions <- sample(REGIONS, 2)
    
    for (team in sampled_teams) {
      for (region in sampled_regions) {
        for (metric in METRICS) {
          # Base values per metric
          base_value <- switch(metric,
            "revenue" = 50000,
            "users_active" = 10000,
            "page_views" = 100000,
            "conversion_rate" = 3.5,
            "support_tickets" = 150,
            "response_time_ms" = 250,
            "error_rate" = 0.5,
            "api_calls" = 500000,
            1000
          )
          
          # Team multiplier
          team_mult <- switch(team,
            "Sales" = 1.2,
            "Marketing" = 1.0,
            "Engineering" = 0.8,
            "Support" = 0.6,
            "Finance" = 0.4,
            1.0
          )
          
          # Region multiplier
          region_mult <- switch(region,
            "North America" = 1.3,
            "Europe" = 1.0,
            "Asia Pacific" = 0.9,
            "Latin America" = 0.6,
            1.0
          )
          
          value <- generate_seasonal_value(
            date, 
            base_value * team_mult * region_mult, 
            variance = 0.15
          )
          
          # Inject some anomalies (about 2% of data)
          if (runif(1) < 0.02) {
            value <- value * sample(c(0.3, 0.5, 2.0, 3.0), 1)
          }
          
          channel <- sample(CHANNELS, 1)
          product <- sample(PRODUCTS, 1)
          
          metrics_data <- rbind(metrics_data, data.frame(
            id = UUIDgenerate(),
            tenant_id = TENANT_ID,
            import_id = NA,
            metric_date = date,
            team = team,
            region = region,
            channel = channel,
            product = product,
            metric_name = metric,
            metric_value = round(value, 4),
            metadata = "{}",
            stringsAsFactors = FALSE
          ))
        }
      }
    }
  }
  
  # Insert batch
  if (nrow(metrics_data) > 0) {
    for (i in seq_len(nrow(metrics_data))) {
      row <- metrics_data[i, ]
      tryCatch({
        dbExecute(conn, sprintf("
          INSERT INTO metrics_data (id, tenant_id, metric_date, team, region, channel, product, metric_name, metric_value, metadata)
          VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', %f, '%s')
        ", row$id, row$tenant_id, row$metric_date, row$team, row$region, 
           row$channel, row$product, row$metric_name, row$metric_value, row$metadata))
      }, error = function(e) {
        # Skip duplicates
      })
    }
    total_inserted <- total_inserted + nrow(metrics_data)
  }
  
  cat(sprintf("  Processed dates %s to %s (%d records)\n", 
              min(batch_dates), max(batch_dates), nrow(metrics_data)))
}

cat(sprintf("Generated %d metric records\n\n", total_inserted))

# Get admin user ID
admin_user <- dbGetQuery(conn, sprintf("
  SELECT id FROM users WHERE tenant_id = '%s' AND role = 'admin' LIMIT 1
", TENANT_ID))

if (nrow(admin_user) > 0) {
  admin_id <- admin_user$id[1]
  
  # Create some anomalies
  cat("Creating anomaly records...\n")
  
  recent_metrics <- dbGetQuery(conn, sprintf("
    SELECT id, metric_date, metric_name, metric_value, team, region
    FROM metrics_data
    WHERE tenant_id = '%s'
    ORDER BY RAND()
    LIMIT 30
  ", TENANT_ID))
  
  for (i in seq_len(nrow(recent_metrics))) {
    m <- recent_metrics[i, ]
    
    baseline <- m$metric_value * runif(1, 0.8, 1.2)
    zscore <- (m$metric_value - baseline) / (baseline * 0.15)
    
    severity <- if (abs(zscore) >= 4) "high" else if (abs(zscore) >= 3) "medium" else "low"
    
    threshold_low <- baseline - 2 * baseline * 0.15
    threshold_high <- baseline + 2 * baseline * 0.15
    
    direction <- if (zscore > 0) "above" else "below"
    explanation <- sprintf(
      "Value %.2f is %.1f standard deviations %s the baseline (mean: %.2f)",
      m$metric_value, abs(zscore), direction, baseline
    )
    
    dimensions <- toJSON(list(team = m$team, region = m$region), auto_unbox = TRUE)
    
    tryCatch({
      dbExecute(conn, sprintf("
        INSERT INTO anomalies 
          (id, tenant_id, metric_id, detection_date, metric_name, metric_value,
           baseline_value, threshold_low, threshold_high, zscore, severity,
           detection_method, explanation, dimensions)
        VALUES ('%s', '%s', '%s', '%s', '%s', %f, %f, %f, %f, %f, '%s', 'zscore', '%s', '%s')
      ", UUIDgenerate(), TENANT_ID, m$id, m$metric_date, m$metric_name, m$metric_value,
         baseline, threshold_low, threshold_high, zscore, severity,
         gsub("'", "''", explanation), gsub("'", "''", dimensions)))
    }, error = function(e) {
      # Skip errors
    })
  }
  
  cat("Created anomaly records\n\n")
  
  # Create some incidents
  cat("Creating incident records...\n")
  
  anomalies <- dbGetQuery(conn, sprintf("
    SELECT id, metric_name, severity, explanation
    FROM anomalies
    WHERE tenant_id = '%s'
    ORDER BY RAND()
    LIMIT 10
  ", TENANT_ID))
  
  statuses <- c("open", "investigating", "mitigated", "closed")
  
  for (i in seq_len(nrow(anomalies))) {
    a <- anomalies[i, ]
    
    status <- sample(statuses, 1, prob = c(0.3, 0.25, 0.15, 0.3))
    sla_hours <- sample(c(4, 8, 24, 48), 1)
    
    tryCatch({
      incident_id <- UUIDgenerate()
      dbExecute(conn, sprintf("
        INSERT INTO incidents 
          (id, tenant_id, anomaly_id, title, description, status, severity,
           created_by, sla_due_at)
        VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', 
                DATE_ADD(NOW(), INTERVAL %d HOUR))
      ", incident_id, TENANT_ID, a$id, 
         paste("Anomaly detected:", a$metric_name),
         gsub("'", "''", a$explanation),
         status, a$severity, admin_id, sla_hours))
      
      # Add a comment
      if (runif(1) < 0.5) {
        dbExecute(conn, sprintf("
          INSERT INTO incident_comments (id, incident_id, user_id, content)
          VALUES ('%s', '%s', '%s', 'Investigating this anomaly. Initial analysis suggests a data pipeline issue.')
        ", UUIDgenerate(), incident_id, admin_id))
      }
    }, error = function(e) {
      # Skip errors
    })
  }
  
  cat("Created incident records\n\n")
  
  # Create audit logs
  cat("Creating audit log entries...\n")
  
  actions <- c("login", "data_import", "incident_create", "incident_update", "export_data")
  
  for (i in 1:30) {
    action <- sample(actions, 1)
    days_ago <- sample(0:30, 1)
    
    entity_type <- switch(action,
      "login" = "session",
      "data_import" = "import",
      "incident_create" = "incident",
      "incident_update" = "incident",
      "export_data" = "export",
      "user"
    )
    
    tryCatch({
      dbExecute(conn, sprintf("
        INSERT INTO audit_logs 
          (id, tenant_id, user_id, action, entity_type, ip_address, created_at)
        VALUES ('%s', '%s', '%s', '%s', '%s', '%s', DATE_SUB(NOW(), INTERVAL %d DAY))
      ", UUIDgenerate(), TENANT_ID, admin_id, action, entity_type,
         paste0("192.168.1.", sample(1:254, 1)), days_ago))
    }, error = function(e) {
      # Skip errors
    })
  }
  
  cat("Created audit log entries\n")
}

# Disconnect
dbDisconnect(conn)

cat("\nDemo data seeding complete!\n")
