-- SignalOps Database Schema - Initial Setup
-- Migration: 001_init.sql
-- Description: Core tables for users, tenants, and base application structure

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create enum types
CREATE TYPE user_role AS ENUM ('admin', 'analyst', 'viewer');
CREATE TYPE user_status AS ENUM ('active', 'inactive', 'locked', 'pending');

-- Tenants table (multi-tenant support)
CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(100) UNIQUE NOT NULL,
    settings JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE
);

-- Users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    role user_role NOT NULL DEFAULT 'viewer',
    status user_status NOT NULL DEFAULT 'pending',
    login_attempts INTEGER DEFAULT 0,
    locked_until TIMESTAMP WITH TIME ZONE,
    last_login_at TIMESTAMP WITH TIME ZONE,
    password_reset_token VARCHAR(255),
    password_reset_expires TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Sessions table
CREATE TABLE sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    token VARCHAR(255) UNIQUE NOT NULL,
    ip_address VARCHAR(45),
    user_agent TEXT,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE
);

-- Data imports table
CREATE TABLE data_imports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    filename VARCHAR(255) NOT NULL,
    original_filename VARCHAR(255) NOT NULL,
    file_size_bytes BIGINT,
    row_count INTEGER,
    valid_row_count INTEGER,
    error_count INTEGER DEFAULT 0,
    status VARCHAR(50) DEFAULT 'pending',
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    error_message TEXT,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Staging data table (temporary storage before validation)
CREATE TABLE staging_data (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    import_id UUID REFERENCES data_imports(id) ON DELETE CASCADE,
    row_num INTEGER NOT NULL,
    raw_data JSONB NOT NULL,
    is_valid BOOLEAN,
    validation_errors JSONB DEFAULT '[]',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Metrics data table (validated and committed data)
CREATE TABLE metrics_data (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    import_id UUID REFERENCES data_imports(id) ON DELETE SET NULL,
    metric_date DATE NOT NULL,
    team VARCHAR(100),
    region VARCHAR(100),
    channel VARCHAR(100),
    product VARCHAR(100),
    metric_name VARCHAR(255) NOT NULL,
    metric_value NUMERIC(20, 4) NOT NULL,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Validation rules table
CREATE TABLE validation_rules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    rule_type VARCHAR(50) NOT NULL,
    column_name VARCHAR(100) NOT NULL,
    parameters JSONB DEFAULT '{}',
    severity VARCHAR(20) DEFAULT 'error',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Validation results table
CREATE TABLE validation_results (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    import_id UUID REFERENCES data_imports(id) ON DELETE CASCADE,
    rule_id UUID REFERENCES validation_rules(id) ON DELETE SET NULL,
    staging_row_id UUID REFERENCES staging_data(id) ON DELETE CASCADE,
    row_num INTEGER NOT NULL,
    column_name VARCHAR(100),
    error_type VARCHAR(50) NOT NULL,
    error_message TEXT NOT NULL,
    actual_value TEXT,
    expected_value TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

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
);

-- Insert default admin user (password: admin123 - change in production!)
-- Password hash for 'admin123' using sodium
INSERT INTO users (tenant_id, email, password_hash, first_name, last_name, role, status)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'admin@signalops.io',
    '$argon2id$v=19$m=65536,t=3,p=4$c29tZXNhbHRmb3J0ZXN0$HGbBN+xVr1Xvy9bW5LD+H+qPZf6OQxYHpjKM6bYFq3U',
    'Admin',
    'User',
    'admin',
    'active'
);

-- Insert demo users
INSERT INTO users (tenant_id, email, password_hash, first_name, last_name, role, status)
VALUES 
(
    '00000000-0000-0000-0000-000000000001',
    'analyst@signalops.io',
    '$argon2id$v=19$m=65536,t=3,p=4$c29tZXNhbHRmb3J0ZXN0$HGbBN+xVr1Xvy9bW5LD+H+qPZf6OQxYHpjKM6bYFq3U',
    'Sarah',
    'Analyst',
    'analyst',
    'active'
),
(
    '00000000-0000-0000-0000-000000000001',
    'viewer@signalops.io',
    '$argon2id$v=19$m=65536,t=3,p=4$c29tZXNhbHRmb3J0ZXN0$HGbBN+xVr1Xvy9bW5LD+H+qPZf6OQxYHpjKM6bYFq3U',
    'John',
    'Viewer',
    'viewer',
    'active'
);

-- Insert default validation rules
INSERT INTO validation_rules (tenant_id, name, description, rule_type, column_name, parameters, severity)
VALUES
(
    '00000000-0000-0000-0000-000000000001',
    'Date Required',
    'Metric date is required',
    'required',
    'metric_date',
    '{}',
    'error'
),
(
    '00000000-0000-0000-0000-000000000001',
    'Metric Name Required',
    'Metric name is required',
    'required',
    'metric_name',
    '{}',
    'error'
),
(
    '00000000-0000-0000-0000-000000000001',
    'Metric Value Required',
    'Metric value is required',
    'required',
    'metric_value',
    '{}',
    'error'
),
(
    '00000000-0000-0000-0000-000000000001',
    'Metric Value Numeric',
    'Metric value must be a number',
    'type_numeric',
    'metric_value',
    '{}',
    'error'
),
(
    '00000000-0000-0000-0000-000000000001',
    'Valid Date Format',
    'Date must be in YYYY-MM-DD format',
    'type_date',
    'metric_date',
    '{"format": "%Y-%m-%d"}',
    'error'
),
(
    '00000000-0000-0000-0000-000000000001',
    'Positive Value',
    'Metric value should be positive',
    'range',
    'metric_value',
    '{"min": 0}',
    'warning'
);
