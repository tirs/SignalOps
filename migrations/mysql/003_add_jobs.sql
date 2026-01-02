-- SignalOps Database Schema - Job Management (MySQL)
-- Migration: 003_add_jobs.sql
-- Description: Background job tracking and management

-- Jobs table for background task tracking
CREATE TABLE IF NOT EXISTS jobs (
    id VARCHAR(36) PRIMARY KEY,
    tenant_id VARCHAR(36),
    user_id VARCHAR(36),
    job_type ENUM('data_import', 'report_generation', 'anomaly_detection', 
                  'data_export', 'scheduled_import', 'cleanup') NOT NULL,
    status ENUM('pending', 'running', 'completed', 'failed', 'cancelled') NOT NULL DEFAULT 'pending',
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

-- Job logs for detailed execution tracking
CREATE TABLE IF NOT EXISTS job_logs (
    id VARCHAR(36) PRIMARY KEY,
    job_id VARCHAR(36),
    level VARCHAR(20) NOT NULL DEFAULT 'info',
    message TEXT NOT NULL,
    context JSON DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (job_id) REFERENCES jobs(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Scheduled tasks configuration
CREATE TABLE IF NOT EXISTS scheduled_tasks (
    id VARCHAR(36) PRIMARY KEY,
    tenant_id VARCHAR(36),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    task_type ENUM('data_import', 'report_generation', 'anomaly_detection', 
                   'data_export', 'scheduled_import', 'cleanup') NOT NULL,
    cron_expression VARCHAR(100) NOT NULL,
    payload JSON DEFAULT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    last_run_at TIMESTAMP NULL,
    next_run_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Create indexes
CREATE INDEX idx_jobs_tenant ON jobs(tenant_id);
CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_type ON jobs(job_type);
CREATE INDEX idx_jobs_created ON jobs(created_at DESC);
CREATE INDEX idx_job_logs_job ON job_logs(job_id);
CREATE INDEX idx_scheduled_tenant ON scheduled_tasks(tenant_id);

-- View for recent job summary
CREATE OR REPLACE VIEW recent_jobs_summary AS
SELECT 
    j.id,
    j.job_type,
    j.status,
    j.progress,
    j.progress_message,
    j.error_message,
    u.email as user_email,
    j.started_at,
    j.completed_at,
    TIMESTAMPDIFF(SECOND, j.started_at, COALESCE(j.completed_at, NOW())) as duration_seconds,
    j.created_at
FROM jobs j
LEFT JOIN users u ON j.user_id = u.id
ORDER BY j.created_at DESC;
