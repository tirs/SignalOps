-- SignalOps Database Schema - Initial Setup (MySQL)
-- Migration: 001_init.sql
-- Description: Core tables for users, tenants, and base application structure

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

-- Staging data table (temporary storage before validation)
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

-- Metrics data table (validated and committed data)
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

-- Create indexes for performance
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

-- Insert default tenant
INSERT INTO tenants (id, name, slug, settings)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'Default Tenant',
    'default',
    '{"theme": "dark", "timezone": "UTC"}'
) ON DUPLICATE KEY UPDATE name = name;

-- Insert default admin user (password: admin123 - change in production!)
INSERT INTO users (id, tenant_id, email, password_hash, first_name, last_name, role, status)
VALUES (
    '00000000-0000-0000-0000-000000000010',
    '00000000-0000-0000-0000-000000000001',
    'admin@signalops.io',
    '$argon2id$v=19$m=65536,t=3,p=4$c29tZXNhbHRmb3J0ZXN0$HGbBN+xVr1Xvy9bW5LD+H+qPZf6OQxYHpjKM6bYFq3U',
    'Admin',
    'User',
    'admin',
    'active'
) ON DUPLICATE KEY UPDATE email = email;

-- Insert demo users
INSERT INTO users (id, tenant_id, email, password_hash, first_name, last_name, role, status)
VALUES 
(
    '00000000-0000-0000-0000-000000000011',
    '00000000-0000-0000-0000-000000000001',
    'analyst@signalops.io',
    '$argon2id$v=19$m=65536,t=3,p=4$c29tZXNhbHRmb3J0ZXN0$HGbBN+xVr1Xvy9bW5LD+H+qPZf6OQxYHpjKM6bYFq3U',
    'Sarah',
    'Analyst',
    'analyst',
    'active'
),
(
    '00000000-0000-0000-0000-000000000012',
    '00000000-0000-0000-0000-000000000001',
    'viewer@signalops.io',
    '$argon2id$v=19$m=65536,t=3,p=4$c29tZXNhbHRmb3J0ZXN0$HGbBN+xVr1Xvy9bW5LD+H+qPZf6OQxYHpjKM6bYFq3U',
    'John',
    'Viewer',
    'viewer',
    'active'
) ON DUPLICATE KEY UPDATE email = email;

-- Insert default validation rules
INSERT INTO validation_rules (id, tenant_id, name, description, rule_type, column_name, parameters, severity)
VALUES
(
    '00000000-0000-0000-0000-000000000101',
    '00000000-0000-0000-0000-000000000001',
    'Date Required',
    'Metric date is required',
    'required',
    'metric_date',
    '{}',
    'error'
),
(
    '00000000-0000-0000-0000-000000000102',
    '00000000-0000-0000-0000-000000000001',
    'Metric Name Required',
    'Metric name is required',
    'required',
    'metric_name',
    '{}',
    'error'
),
(
    '00000000-0000-0000-0000-000000000103',
    '00000000-0000-0000-0000-000000000001',
    'Metric Value Required',
    'Metric value is required',
    'required',
    'metric_value',
    '{}',
    'error'
),
(
    '00000000-0000-0000-0000-000000000104',
    '00000000-0000-0000-0000-000000000001',
    'Metric Value Numeric',
    'Metric value must be a number',
    'type_numeric',
    'metric_value',
    '{}',
    'error'
),
(
    '00000000-0000-0000-0000-000000000105',
    '00000000-0000-0000-0000-000000000001',
    'Valid Date Format',
    'Date must be in YYYY-MM-DD format',
    'type_date',
    'metric_date',
    '{"format": "%Y-%m-%d"}',
    'error'
),
(
    '00000000-0000-0000-0000-000000000106',
    '00000000-0000-0000-0000-000000000001',
    'Positive Value',
    'Metric value should be positive',
    'range',
    'metric_value',
    '{"min": 0}',
    'warning'
) ON DUPLICATE KEY UPDATE name = name;
