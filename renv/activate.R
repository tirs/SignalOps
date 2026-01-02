# renv activation script
# This is a placeholder for the renv library loader
# Run renv::init() to properly initialize renv for this project

local({
  
  # Check if renv is installed
  if (!requireNamespace("renv", quietly = TRUE)) {
    message("renv is not installed. Install with: install.packages('renv')")
    return(invisible())
  }
  
  # Try to activate the project
  tryCatch({
    renv::activate()
  }, error = function(e) {
    message("renv project not initialized. Run renv::init() to set up.")
  })
  
})
