-- ============================================================
-- SignalOps Complete Database Schema for MySQL
-- Run this in phpMyAdmin SQL tab
-- ============================================================

-- Tenants table (multi-tenant support)
CREATE TABLE IF NOT EXISTS tenants (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(100) UNIQUE NOT NULL,
    settings JSON DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id VARCHAR(36) PRIMARY KEY,
    tenant_id VARCHAR(36),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    role ENUM('admin', 'analyst', 'viewer') NOT NULL DEFAULT 'viewer',
    status ENUM('active', 'inactive', 'locked', 'pending') NOT NULL DEFAULT 'pending',
    login_attempts INT DEFAULT 0,
    locked_until TIMESTAMP NULL,
    last_login_at TIMESTAMP NULL,
    password_reset_token VARCHAR(255),
    password_reset_expires TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Sessions table
CREATE TABLE IF NOT EXISTS sessions (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36),
    token VARCHAR(255) UNIQUE NOT NULL,
    ip_address VARCHAR(45),
    user_agent TEXT,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Data imports table
CREATE TABLE IF NOT EXISTS data_imports (
    id VARCHAR(36) PRIMARY KEY,
    tenant_id VARCHAR(36),
    user_id VARCHAR(36),
    filename VARCHAR(255) NOT NULL,
    original_filename VARCHAR(255) NOT NULL,
    file_size_bytes BIGINT,
    row_count INT,
    valid_row_count INT,
    error_count INT DEFAULT 0,
    status VARCHAR(50) DEFAULT 'pending',
    started_at TIMESTAMP NULL,
    completed_at TIMESTAMP NULL,
    error_message TEXT,
    metadata JSON DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Staging data table
CREATE TABLE IF NOT EXISTS staging_data (
    id VARCHAR(36) PRIMARY KEY,
    import_id VARCHAR(36),
    row_num INT NOT NULL,
    raw_data JSON NOT NULL,
    is_valid BOOLEAN,
    validation_errors JSON DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (import_id) REFERENCES data_imports(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Metrics data table
CREATE TABLE IF NOT EXISTS metrics_data (
    id VARCHAR(36) PRIMARY KEY,
    tenant_id VARCHAR(36),
    import_id VARCHAR(36),
    metric_date DATE NOT NULL,
    team VARCHAR(100),
    region VARCHAR(100),
    channel VARCHAR(100),
    product VARCHAR(100),
    metric_name VARCHAR(255) NOT NULL,
    metric_value DECIMAL(20, 4) NOT NULL,
    metadata JSON DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (import_id) REFERENCES data_imports(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Validation rules table
CREATE TABLE IF NOT EXISTS validation_rules (
    id VARCHAR(36) PRIMARY KEY,
    tenant_id VARCHAR(36),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    rule_type VARCHAR(50) NOT NULL,
    column_name VARCHAR(100) NOT NULL,
    parameters JSON DEFAULT NULL,
    severity VARCHAR(20) DEFAULT 'error',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Validation results table
CREATE TABLE IF NOT EXISTS validation_results (
    id VARCHAR(36) PRIMARY KEY,
    import_id VARCHAR(36),
    rule_id VARCHAR(36),
    staging_row_id VARCHAR(36),
    row_num INT NOT NULL,
    column_name VARCHAR(100),
    error_type VARCHAR(50) NOT NULL,
    error_message TEXT NOT NULL,
    actual_value TEXT,
    expected_value TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (import_id) REFERENCES data_imports(id) ON DELETE CASCADE,
    FOREIGN KEY (rule_id) REFERENCES validation_rules(id) ON DELETE SET NULL,
    FOREIGN KEY (staging_row_id) REFERENCES staging_data(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Audit log table
CREATE TABLE IF NOT EXISTS audit_logs (
    id VARCHAR(36) PRIMARY KEY,
    tenant_id VARCHAR(36),
    user_id VARCHAR(36),
    session_id VARCHAR(36),
    action VARCHAR(50) NOT NULL,
    entity_type VARCHAR(100),
    entity_id VARCHAR(36),
    old_values JSON,
    new_values JSON,
    ip_address VARCHAR(45),
    user_agent TEXT,
    metadata JSON DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
    FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Jobs table
CREATE TABLE IF NOT EXISTS jobs (
    id VARCHAR(36) PRIMARY KEY,
    tenant_id VARCHAR(36),
    user_id VARCHAR(36),
    job_type VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    priority INT DEFAULT 5,
    payload JSON DEFAULT NULL,
    result JSON,
    progress INT DEFAULT 0,
    progress_message VARCHAR(255),
    error_message TEXT,
    error_trace TEXT,
    attempts INT DEFAULT 0,
    max_attempts INT DEFAULT 3,
    scheduled_at TIMESTAMP NULL,
    started_at TIMESTAMP NULL,
    completed_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Job logs table
CREATE TABLE IF NOT EXISTS job_logs (
    id VARCHAR(36) PRIMARY KEY,
    job_id VARCHAR(36),
    level VARCHAR(20) NOT NULL DEFAULT 'info',
    message TEXT NOT NULL,
    context JSON DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (job_id) REFERENCES jobs(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Scheduled tasks table
CREATE TABLE IF NOT EXISTS scheduled_tasks (
    id VARCHAR(36) PRIMARY KEY,
    tenant_id VARCHAR(36),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    task_type VARCHAR(50) NOT NULL,
    cron_expression VARCHAR(100) NOT NULL,
    payload JSON DEFAULT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    last_run_at TIMESTAMP NULL,
    next_run_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Anomalies table
CREATE TABLE IF NOT EXISTS anomalies (
    id VARCHAR(36) PRIMARY KEY,
    tenant_id VARCHAR(36),
    metric_id VARCHAR(36),
    detection_date DATE NOT NULL,
    metric_name VARCHAR(255) NOT NULL,
    metric_value DECIMAL(20, 4) NOT NULL,
    baseline_value DECIMAL(20, 4),
    threshold_low DECIMAL(20, 4),
    threshold_high DECIMAL(20, 4),
    zscore DECIMAL(10, 4),
    severity ENUM('low', 'medium', 'high', 'critical') NOT NULL,
    detection_method VARCHAR(50) DEFAULT 'zscore',
    explanation TEXT,
    dimensions JSON DEFAULT NULL,
    is_acknowledged BOOLEAN DEFAULT FALSE,
    acknowledged_by VARCHAR(36),
    acknowledged_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (metric_id) REFERENCES metrics_data(id) ON DELETE SET NULL,
    FOREIGN KEY (acknowledged_by) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Incidents table
CREATE TABLE IF NOT EXISTS incidents (
    id VARCHAR(36) PRIMARY KEY,
    tenant_id VARCHAR(36),
    anomaly_id VARCHAR(36),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    status ENUM('open', 'investigating', 'mitigated', 'closed', 'false_positive') NOT NULL DEFAULT 'open',
    severity ENUM('low', 'medium', 'high', 'critical') NOT NULL,
    assigned_to VARCHAR(36),
    created_by VARCHAR(36),
    sla_due_at TIMESTAMP NULL,
    resolved_at TIMESTAMP NULL,
    resolution_notes TEXT,
    root_cause TEXT,
    impact TEXT,
    metadata JSON DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (anomaly_id) REFERENCES anomalies(id) ON DELETE SET NULL,
    FOREIGN KEY (assigned_to) REFERENCES users(id),
    FOREIGN KEY (created_by) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Incident comments table
CREATE TABLE IF NOT EXISTS incident_comments (
    id VARCHAR(36) PRIMARY KEY,
    incident_id VARCHAR(36),
    user_id VARCHAR(36),
    content TEXT NOT NULL,
    is_internal BOOLEAN DEFAULT FALSE,
    attachments JSON DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (incident_id) REFERENCES incidents(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Incident status history table
CREATE TABLE IF NOT EXISTS incident_status_history (
    id VARCHAR(36) PRIMARY KEY,
    incident_id VARCHAR(36),
    user_id VARCHAR(36),
    old_status VARCHAR(20),
    new_status VARCHAR(20) NOT NULL,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (incident_id) REFERENCES incidents(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Anomaly baselines table
CREATE TABLE IF NOT EXISTS anomaly_baselines (
    id VARCHAR(36) PRIMARY KEY,
    tenant_id VARCHAR(36),
    metric_name VARCHAR(255) NOT NULL,
    dimensions_hash VARCHAR(64) NOT NULL,
    dimensions JSON DEFAULT NULL,
    baseline_mean DECIMAL(20, 4),
    baseline_std DECIMAL(20, 4),
    baseline_median DECIMAL(20, 4),
    baseline_mad DECIMAL(20, 4),
    data_points INT,
    calculated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    window_start DATE,
    window_end DATE,
    UNIQUE KEY unique_baseline (tenant_id, metric_name, dimensions_hash),
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Schema migrations tracking
CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(100) PRIMARY KEY,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_tenant ON users(tenant_id);
CREATE INDEX idx_sessions_token ON sessions(token);
CREATE INDEX idx_sessions_user ON sessions(user_id);
CREATE INDEX idx_data_imports_tenant ON data_imports(tenant_id);
CREATE INDEX idx_staging_import ON staging_data(import_id);
CREATE INDEX idx_metrics_tenant ON metrics_data(tenant_id);
CREATE INDEX idx_metrics_date ON metrics_data(metric_date);
CREATE INDEX idx_metrics_name ON metrics_data(metric_name);
CREATE INDEX idx_validation_results_import ON validation_results(import_id);
CREATE INDEX idx_audit_tenant ON audit_logs(tenant_id);
CREATE INDEX idx_audit_user ON audit_logs(user_id);
CREATE INDEX idx_audit_action ON audit_logs(action);
CREATE INDEX idx_audit_created ON audit_logs(created_at);
CREATE INDEX idx_jobs_tenant ON jobs(tenant_id);
CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_created ON jobs(created_at);
CREATE INDEX idx_anomalies_tenant ON anomalies(tenant_id);
CREATE INDEX idx_anomalies_date ON anomalies(detection_date);
CREATE INDEX idx_anomalies_severity ON anomalies(severity);
CREATE INDEX idx_incidents_tenant ON incidents(tenant_id);
CREATE INDEX idx_incidents_status ON incidents(status);
CREATE INDEX idx_incidents_created ON incidents(created_at);

-- ============================================================
-- DEFAULT DATA
-- ============================================================

-- Insert default tenant
INSERT INTO tenants (id, name, slug, settings) VALUES 
('00000000-0000-0000-0000-000000000001', 'Default Tenant', 'default', '{"theme": "dark", "timezone": "UTC"}')
ON DUPLICATE KEY UPDATE name = name;

-- Insert admin user (password: admin123)
INSERT INTO users (id, tenant_id, email, password_hash, first_name, last_name, role, status) VALUES 
('00000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000001', 'admin@signalops.io', '$argon2id$v=19$m=65536,t=3,p=4$c29tZXNhbHRmb3J0ZXN0$HGbBN+xVr1Xvy9bW5LD+H+qPZf6OQxYHpjKM6bYFq3U', 'Admin', 'User', 'admin', 'active')
ON DUPLICATE KEY UPDATE email = email;

-- Insert analyst user (password: admin123)
INSERT INTO users (id, tenant_id, email, password_hash, first_name, last_name, role, status) VALUES 
('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001', 'analyst@signalops.io', '$argon2id$v=19$m=65536,t=3,p=4$c29tZXNhbHRmb3J0ZXN0$HGbBN+xVr1Xvy9bW5LD+H+qPZf6OQxYHpjKM6bYFq3U', 'Sarah', 'Analyst', 'analyst', 'active')
ON DUPLICATE KEY UPDATE email = email;

-- Insert viewer user (password: admin123)
INSERT INTO users (id, tenant_id, email, password_hash, first_name, last_name, role, status) VALUES 
('00000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-000000000001', 'viewer@signalops.io', '$argon2id$v=19$m=65536,t=3,p=4$c29tZXNhbHRmb3J0ZXN0$HGbBN+xVr1Xvy9bW5LD+H+qPZf6OQxYHpjKM6bYFq3U', 'John', 'Viewer', 'viewer', 'active')
ON DUPLICATE KEY UPDATE email = email;

-- Insert default validation rules
INSERT INTO validation_rules (id, tenant_id, name, description, rule_type, column_name, parameters, severity) VALUES
('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000001', 'Date Required', 'Metric date is required', 'required', 'metric_date', '{}', 'error'),
('00000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000001', 'Metric Name Required', 'Metric name is required', 'required', 'metric_name', '{}', 'error'),
('00000000-0000-0000-0000-000000000103', '00000000-0000-0000-0000-000000000001', 'Metric Value Required', 'Metric value is required', 'required', 'metric_value', '{}', 'error'),
('00000000-0000-0000-0000-000000000104', '00000000-0000-0000-0000-000000000001', 'Metric Value Numeric', 'Metric value must be a number', 'type_numeric', 'metric_value', '{}', 'error'),
('00000000-0000-0000-0000-000000000105', '00000000-0000-0000-0000-000000000001', 'Valid Date Format', 'Date must be in YYYY-MM-DD format', 'type_date', 'metric_date', '{"format": "%Y-%m-%d"}', 'error'),
('00000000-0000-0000-0000-000000000106', '00000000-0000-0000-0000-000000000001', 'Positive Value', 'Metric value should be positive', 'range', 'metric_value', '{"min": 0}', 'warning')
ON DUPLICATE KEY UPDATE name = name;

-- Record migration
INSERT INTO schema_migrations (version) VALUES ('full_schema_v1')
ON DUPLICATE KEY UPDATE applied_at = CURRENT_TIMESTAMP;

-- ============================================================
-- DONE! Database is ready.
-- ============================================================
