# SignalOps

**Production-Grade Multi-Tenant Analytics & Operations Dashboard**

A comprehensive Shiny application built to enterprise standards, featuring authenticated role-based access, data validation pipelines, anomaly detection, incident workflows, and full audit trails.

---

## Features

### Authentication & Security
- Email/password login with Argon2 password hashing
- Role-based access control (Admin, Analyst, Viewer)
- Session management with configurable timeouts
- Account lockout protection
- Password reset flow
- Complete audit trail logging

### Data Management
- CSV upload with staging and validation pipeline
- Configurable validation rules engine
- Versioned imports with rollback capability
- Server-side pagination for large datasets
- Data export (CSV)

### Analytics
- Real-time KPI dashboards
- Trend visualizations with Plotly
- Drill-down data explorer
- Dimension filtering (team, region, channel, product)

### Anomaly Detection
- Statistical baseline computation (mean/std, median/MAD)
- Z-score based anomaly detection
- Configurable severity thresholds
- Anomaly acknowledgment workflow

### Incident Management
- Create incidents from anomalies
- Status workflow (Open, Investigating, Mitigated, Closed)
- User assignment
- Comments and internal notes
- SLA tracking
- Resolution documentation

### Reporting
- KPI summary reports
- Anomaly reports
- Incident reports
- Data exports (metrics, anomalies, incidents, audit log)

### Administration
- User management
- System health monitoring
- Active session tracking
- Job history and status
- Configuration management

---

## Architecture

```
signalops/
  app/
    app.R                    # Main Shiny application
    global.R                 # Global configuration and initialization
    config.yml               # Application configuration
    R/
      modules/               # Shiny UI modules
        mod_login.R          # Authentication UI
        mod_nav.R            # Navigation and layout
        mod_overview.R       # Dashboard overview
        mod_explorer.R       # Data explorer
        mod_quality.R        # Data quality management
        mod_anomalies.R      # Anomaly detection
        mod_incidents.R      # Incident management
        mod_reports.R        # Reporting and exports
        mod_admin.R          # Administration
      services/              # Business logic layer
        db_pool.R            # Database connection pooling
        auth_service.R       # Authentication and authorization
        import_service.R     # Data import pipeline
        validation_service.R # Validation rules engine
        anomaly_service.R    # Anomaly detection
        incident_service.R   # Incident workflow
        report_service.R     # Report generation
      utils/                 # Utility functions
        logging.R            # Structured logging
        caching.R            # Performance caching
        helpers.R            # Common utilities
    www/
      styles.css             # Application styling
      logo.svg               # Application logo
  migrations/                # Database schema migrations
    001_init.sql             # Core tables
    002_add_audit.sql        # Audit logging
    003_add_jobs.sql         # Job management
    004_add_anomalies.sql    # Anomaly and incident tables
  docker/
    Dockerfile               # Multi-stage production build
    docker-compose.yml       # Full stack deployment
    nginx.conf               # Reverse proxy configuration
  scripts/
    run_migrations.R         # Database migration runner
    seed_demo_data.R         # Demo data generator
  tests/
    testthat/                # Unit tests
```

---

## Technology Stack

| Component | Technology |
|-----------|------------|
| Frontend | Shiny + bslib + plotly |
| Backend | R with pool + DBI |
| Database | MySQL 8.0 (Hostinger) |
| Authentication | Argon2 (sodium) |
| Caching | memoise + cachem |
| Logging | logger (JSON format) |
| Container | Docker + docker-compose |
| Reverse Proxy | Nginx with SSL |
| CI/CD | GitHub Actions |

---

## Quick Start

### Prerequisites

- R >= 4.1.0
- MySQL 8.0+ (remote database on Hostinger is pre-configured)
- Docker (optional, for containerized deployment)

### Local Development

1. **Clone the repository**
```bash
git clone https://github.com/yourusername/signalops.git
cd signalops
```

2. **Install R dependencies**
```r
install.packages(c(
  "shiny", "bslib", "DBI", "pool", "RMariaDB", "dplyr", "dbplyr",
  "ggplot2", "plotly", "DT", "sodium", "config", "jsonlite",
  "lubridate", "purrr", "tibble", "tidyr", "readr", "stringr",
  "glue", "memoise", "cachem", "logger", "uuid", "shinyjs",
  "shinyWidgets", "waiter", "htmltools", "promises", "future"
))
```

3. **Database Configuration**

The application is configured to use a remote MySQL database on Hostinger:
- Host: `srv1539.hstgr.io`
- Database: `u280406916_SignalOps`
- Port: `3306`

Environment variables (optional, defaults are set in config.yml):
```bash
export DB_HOST=srv1539.hstgr.io
export DB_PORT=3306
export DB_NAME=u280406916_SignalOps
export DB_USER=u280406916_SignalOps
export DB_PASSWORD=your_password
```

4. **Run database migrations**
```r
source("scripts/run_migrations.R")
```

5. **Seed demo data (optional)**
```r
source("scripts/seed_demo_data.R")
```

6. **Start the application**
```r
setwd("app")
shiny::runApp(port = 3838)
```

7. **Access the application**
Open http://localhost:3838 in your browser.

### Default Credentials

| Role | Email | Password |
|------|-------|----------|
| Admin | admin@signalops.io | admin123 |
| Analyst | analyst@signalops.io | admin123 |
| Viewer | viewer@signalops.io | admin123 |

---

## Docker Deployment

### Development

```bash
cd docker
docker-compose up -d
```

### Production

1. **Configure environment**
```bash
cp docker/env.example docker/.env
# Edit .env with production values
```

2. **Set up SSL certificates**
```bash
mkdir docker/ssl
# Add your cert.pem and key.pem files
```

3. **Deploy**
```bash
docker-compose -f docker/docker-compose.yml up -d
```

---

## Configuration

Configuration is managed via `app/config.yml` with environment-specific overrides:

```yaml
default:
  app:
    name: "SignalOps"
    max_upload_mb: 50
    session_timeout_minutes: 60
    
  database:
    host: !expr Sys.getenv("DB_HOST", "localhost")
    port: !expr as.integer(Sys.getenv("DB_PORT", "5432"))
    ...
    
  auth:
    bcrypt_cost: 12
    session_duration_hours: 24
    max_login_attempts: 5
    
  anomaly:
    zscore_threshold_low: 2.0
    zscore_threshold_medium: 3.0
    zscore_threshold_high: 4.0

production:
  inherits: default
  database:
    pool_size: 10
  auth:
    bcrypt_cost: 14
```

---

## Database Schema

### Core Tables
- `tenants` - Multi-tenant organization data
- `users` - User accounts and credentials
- `sessions` - Active user sessions

### Data Tables
- `data_imports` - Import job tracking
- `staging_data` - Temporary import staging
- `metrics_data` - Validated metrics storage
- `validation_rules` - Configurable validation rules
- `validation_results` - Validation error details

### Anomaly & Incident Tables
- `anomaly_baselines` - Computed statistical baselines
- `anomalies` - Detected anomalies
- `incidents` - Incident records
- `incident_comments` - Incident discussion
- `incident_status_history` - Status transitions

### System Tables
- `audit_logs` - Complete audit trail
- `jobs` - Background job tracking
- `job_logs` - Job execution details
- `scheduled_tasks` - Scheduled job configuration

---

## Testing

### Run Unit Tests
```r
testthat::test_dir("tests/testthat")
```

### Run with Coverage
```r
covr::package_coverage()
```

---

## CI/CD Pipeline

The GitHub Actions workflow includes:

1. **Lint** - Code style checking with lintr
2. **Test** - Unit tests with PostgreSQL service
3. **Build** - Docker image build and push
4. **Deploy** - Automated VPS deployment

Required secrets:
- `VPS_HOST` - Production server hostname
- `VPS_USER` - SSH username
- `VPS_SSH_KEY` - SSH private key

---

## Security Considerations

- All passwords are hashed with Argon2 (sodium)
- SQL injection prevention via parameterized queries
- Input validation on all user inputs
- File upload restrictions (size, type)
- HTTPS enforcement in production
- CSRF protection via Shiny session boundaries
- Audit logging for all critical actions
- Role-based authorization at server level

---

## Performance

- Database connection pooling
- Server-side DataTable pagination
- Result caching with configurable TTL
- Chunked file processing
- Async background jobs
- Nginx static file caching
- Gzip compression

---

## Monitoring

### Health Endpoint
```
GET /health
```

### Application Metrics
- Active sessions
- Database connection pool status
- Cache hit rates
- Job execution times

### Logs
Structured JSON logging to `logs/signalops.log`:
```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "level": "INFO",
  "message": "User logged in",
  "user_id": "abc123",
  "ip": "192.168.1.1"
}
```

---

## License

MIT License - see [LICENSE](LICENSE) for details.

---

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes with tests
4. Submit a pull request

All contributions must pass CI checks and include appropriate tests.
