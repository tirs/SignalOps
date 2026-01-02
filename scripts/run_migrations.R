# SignalOps Database Migration Runner (MySQL)
# Applies SQL migrations in order

library(DBI)
library(RMariaDB)

# Configuration
config <- list(
  host = Sys.getenv("DB_HOST", "srv1539.hstgr.io"),
  port = as.integer(Sys.getenv("DB_PORT", "3306")),
  dbname = Sys.getenv("DB_NAME", "u280406916_SignalOps"),
  user = Sys.getenv("DB_USER", "u280406916_SignalOps"),
  password = Sys.getenv("DB_PASSWORD", "6GSaZLVVPMi>")
)

# Migration directory (use MySQL migrations)
MIGRATIONS_DIR <- file.path(getwd(), "migrations", "mysql")

cat("SignalOps Migration Runner (MySQL)\n")
cat("===================================\n\n")

# Connect to database
cat("Connecting to database...\n")
cat(sprintf("  Host: %s\n", config$host))
cat(sprintf("  Database: %s\n", config$dbname))

conn <- tryCatch({
  DBI::dbConnect(
    RMariaDB::MariaDB(),
    host = config$host,
    port = config$port,
    dbname = config$dbname,
    username = config$user,
    password = config$password
  )
}, error = function(e) {
  cat(sprintf("Error connecting to database: %s\n", e$message))
  quit(status = 1)
})

cat("Connected successfully!\n\n")

# Create migrations tracking table if not exists
cat("Checking migrations table...\n")
tryCatch({
  dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version VARCHAR(100) PRIMARY KEY,
      applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  ")
}, error = function(e) {
  cat(sprintf("Note: %s\n", e$message))
})

# Get applied migrations
applied <- tryCatch({
  dbGetQuery(conn, "SELECT version FROM schema_migrations ORDER BY version")
}, error = function(e) {
  data.frame(version = character())
})
applied_versions <- applied$version

# Get migration files
migration_files <- list.files(
  MIGRATIONS_DIR, 
  pattern = "^\\d+.*\\.sql$", 
  full.names = TRUE
)
migration_files <- sort(migration_files)

if (length(migration_files) == 0) {
  cat("No migration files found in:", MIGRATIONS_DIR, "\n")
  dbDisconnect(conn)
  quit(status = 0)
}

cat(sprintf("Found %d migration files\n\n", length(migration_files)))

# Apply pending migrations
pending_count <- 0
success_count <- 0
error_count <- 0

for (file_path in migration_files) {
  filename <- basename(file_path)
  version <- sub("\\.sql$", "", filename)
  
  if (version %in% applied_versions) {
    cat(sprintf("  [SKIP] %s (already applied)\n", filename))
    next
  }
  
  pending_count <- pending_count + 1
  cat(sprintf("  [APPLY] %s\n", filename))
  
  # Read migration file
  sql <- readLines(file_path, warn = FALSE)
  sql <- paste(sql, collapse = "\n")
  
  tryCatch({
    # Split by delimiter changes and semicolons
    # Handle DELIMITER statements for triggers
    if (grepl("DELIMITER", sql)) {
      # Execute the entire file as-is for complex migrations with triggers
      # Split by DELIMITER markers
      parts <- strsplit(sql, "DELIMITER //|DELIMITER ;")[[1]]
      
      for (part in parts) {
        part <- trimws(part)
        if (nchar(part) > 0) {
          # Split regular statements
          statements <- strsplit(part, ";")[[1]]
          statements <- trimws(statements)
          statements <- statements[nchar(statements) > 0]
          
          for (stmt in statements) {
            if (nchar(stmt) > 0 && !grepl("^--", stmt) && !grepl("^/\\*", stmt)) {
              tryCatch({
                dbExecute(conn, stmt)
              }, error = function(e) {
                if (!grepl("already exists|Duplicate", e$message)) {
                  cat(sprintf("         Warning: %s\n", e$message))
                }
              })
            }
          }
        }
      }
    } else {
      # Simple migration without delimiters
      statements <- strsplit(sql, ";")[[1]]
      statements <- trimws(statements)
      statements <- statements[nchar(statements) > 0]
      
      for (stmt in statements) {
        if (nchar(stmt) > 0 && !grepl("^--", stmt) && !grepl("^/\\*", stmt)) {
          tryCatch({
            dbExecute(conn, stmt)
          }, error = function(e) {
            if (!grepl("already exists|Duplicate", e$message)) {
              cat(sprintf("         Warning: %s\n", e$message))
            }
          })
        }
      }
    }
    
    # Record migration
    dbExecute(conn, 
              sprintf("INSERT INTO schema_migrations (version) VALUES ('%s')", version))
    
    success_count <- success_count + 1
    cat(sprintf("         Applied successfully\n"))
    
  }, error = function(e) {
    error_count <<- error_count + 1
    cat(sprintf("         ERROR: %s\n", e$message))
  })
}

# Summary
cat("\n")
cat("Migration Summary\n")
cat("-----------------\n")
cat(sprintf("  Total files: %d\n", length(migration_files)))
cat(sprintf("  Already applied: %d\n", length(migration_files) - pending_count))
cat(sprintf("  Pending: %d\n", pending_count))
cat(sprintf("  Applied now: %d\n", success_count))
cat(sprintf("  Errors: %d\n", error_count))

# Disconnect
dbDisconnect(conn)

if (error_count > 0) {
  cat("\nMigrations completed with some errors.\n")
} else {
  cat("\nMigrations complete.\n")
}
