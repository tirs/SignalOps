-- SignalOps Database Schema - Job Management
-- Migration: 003_add_jobs.sql
-- Description: Background job tracking and management

-- Job status enum
CREATE TYPE job_status AS ENUM ('pending', 'running', 'completed', 'failed', 'cancelled');
CREATE TYPE job_type AS ENUM ('data_import', 'report_generation', 'anomaly_detection', 'data_export', 'scheduled_import', 'cleanup');

-- Jobs table for background task tracking
CREATE TABLE jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    job_type job_type NOT NULL,
    status job_status NOT NULL DEFAULT 'pending',
    priority INTEGER DEFAULT 5,
    payload JSONB DEFAULT '{}',
    result JSONB,
    progress INTEGER DEFAULT 0,
    progress_message VARCHAR(255),
    error_message TEXT,
    error_trace TEXT,
    attempts INTEGER DEFAULT 0,
    max_attempts INTEGER DEFAULT 3,
    scheduled_at TIMESTAMP WITH TIME ZONE,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Job logs for detailed execution tracking
CREATE TABLE job_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_id UUID REFERENCES jobs(id) ON DELETE CASCADE,
    level VARCHAR(20) NOT NULL DEFAULT 'info',
    message TEXT NOT NULL,
    context JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Scheduled tasks configuration
CREATE TABLE scheduled_tasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    task_type job_type NOT NULL,
    cron_expression VARCHAR(100) NOT NULL,
    payload JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT TRUE,
    last_run_at TIMESTAMP WITH TIME ZONE,
    next_run_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes
CREATE INDEX idx_jobs_tenant ON jobs(tenant_id);
CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_type ON jobs(job_type);
CREATE INDEX idx_jobs_created ON jobs(created_at DESC);
CREATE INDEX idx_job_logs_job ON job_logs(job_id);
CREATE INDEX idx_scheduled_tenant ON scheduled_tasks(tenant_id);

-- Apply updated_at trigger
CREATE TRIGGER update_jobs_updated_at
    BEFORE UPDATE ON jobs
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_scheduled_updated_at
    BEFORE UPDATE ON scheduled_tasks
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- View for recent job summary
CREATE VIEW recent_jobs_summary AS
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
    EXTRACT(EPOCH FROM (COALESCE(j.completed_at, CURRENT_TIMESTAMP) - j.started_at)) as duration_seconds,
    j.created_at
FROM jobs j
LEFT JOIN users u ON j.user_id = u.id
ORDER BY j.created_at DESC;
