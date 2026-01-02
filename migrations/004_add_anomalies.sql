-- SignalOps Database Schema - Anomaly Detection
-- Migration: 004_add_anomalies.sql
-- Description: Anomaly detection results and incident management

-- Severity enum
CREATE TYPE severity_level AS ENUM ('low', 'medium', 'high', 'critical');
CREATE TYPE incident_status AS ENUM ('open', 'investigating', 'mitigated', 'closed', 'false_positive');

-- Anomalies table
CREATE TABLE anomalies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    metric_id UUID REFERENCES metrics_data(id) ON DELETE SET NULL,
    detection_date DATE NOT NULL,
    metric_name VARCHAR(255) NOT NULL,
    metric_value NUMERIC(20, 4) NOT NULL,
    baseline_value NUMERIC(20, 4),
    threshold_low NUMERIC(20, 4),
    threshold_high NUMERIC(20, 4),
    zscore NUMERIC(10, 4),
    severity severity_level NOT NULL,
    detection_method VARCHAR(50) DEFAULT 'zscore',
    explanation TEXT,
    dimensions JSONB DEFAULT '{}',
    is_acknowledged BOOLEAN DEFAULT FALSE,
    acknowledged_by UUID REFERENCES users(id),
    acknowledged_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Incidents table (promoted from anomalies)
CREATE TABLE incidents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    anomaly_id UUID REFERENCES anomalies(id) ON DELETE SET NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    status incident_status NOT NULL DEFAULT 'open',
    severity severity_level NOT NULL,
    assigned_to UUID REFERENCES users(id),
    created_by UUID REFERENCES users(id),
    sla_due_at TIMESTAMP WITH TIME ZONE,
    resolved_at TIMESTAMP WITH TIME ZONE,
    resolution_notes TEXT,
    root_cause TEXT,
    impact TEXT,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Incident comments table
CREATE TABLE incident_comments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    incident_id UUID REFERENCES incidents(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    content TEXT NOT NULL,
    is_internal BOOLEAN DEFAULT FALSE,
    attachments JSONB DEFAULT '[]',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Incident status history
CREATE TABLE incident_status_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    incident_id UUID REFERENCES incidents(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    old_status incident_status,
    new_status incident_status NOT NULL,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Anomaly baselines (pre-computed for performance)
CREATE TABLE anomaly_baselines (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    metric_name VARCHAR(255) NOT NULL,
    dimensions_hash VARCHAR(64) NOT NULL,
    dimensions JSONB DEFAULT '{}',
    baseline_mean NUMERIC(20, 4),
    baseline_std NUMERIC(20, 4),
    baseline_median NUMERIC(20, 4),
    baseline_mad NUMERIC(20, 4),
    data_points INTEGER,
    calculated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    window_start DATE,
    window_end DATE,
    UNIQUE(tenant_id, metric_name, dimensions_hash)
);

-- Create indexes
CREATE INDEX idx_anomalies_tenant ON anomalies(tenant_id);
CREATE INDEX idx_anomalies_date ON anomalies(detection_date);
CREATE INDEX idx_anomalies_severity ON anomalies(severity);
CREATE INDEX idx_anomalies_metric ON anomalies(metric_name);
CREATE INDEX idx_incidents_tenant ON incidents(tenant_id);
CREATE INDEX idx_incidents_status ON incidents(status);
CREATE INDEX idx_incidents_assigned ON incidents(assigned_to);
CREATE INDEX idx_incidents_created ON incidents(created_at DESC);
CREATE INDEX idx_incident_comments_incident ON incident_comments(incident_id);
CREATE INDEX idx_baselines_lookup ON anomaly_baselines(tenant_id, metric_name, dimensions_hash);

-- Apply updated_at trigger
CREATE TRIGGER update_incidents_updated_at
    BEFORE UPDATE ON incidents
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_comments_updated_at
    BEFORE UPDATE ON incident_comments
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Function to auto-create status history on incident status change
CREATE OR REPLACE FUNCTION log_incident_status_change()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO incident_status_history (incident_id, old_status, new_status)
        VALUES (NEW.id, OLD.status, NEW.status);
    END IF;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER incident_status_change_trigger
    AFTER UPDATE ON incidents
    FOR EACH ROW
    EXECUTE FUNCTION log_incident_status_change();

-- View for incident dashboard
CREATE VIEW incident_dashboard AS
SELECT 
    i.id,
    i.title,
    i.status,
    i.severity,
    i.created_at,
    i.sla_due_at,
    CASE 
        WHEN i.sla_due_at < CURRENT_TIMESTAMP AND i.status NOT IN ('closed', 'false_positive') 
        THEN TRUE 
        ELSE FALSE 
    END as sla_breached,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - i.created_at)) / 3600 as age_hours,
    u_assigned.email as assigned_to_email,
    u_assigned.first_name || ' ' || u_assigned.last_name as assigned_to_name,
    u_created.email as created_by_email,
    (SELECT COUNT(*) FROM incident_comments ic WHERE ic.incident_id = i.id) as comment_count
FROM incidents i
LEFT JOIN users u_assigned ON i.assigned_to = u_assigned.id
LEFT JOIN users u_created ON i.created_by = u_created.id;

-- View for anomaly summary
CREATE VIEW anomaly_summary AS
SELECT 
    a.tenant_id,
    a.detection_date,
    a.metric_name,
    a.severity,
    COUNT(*) as anomaly_count,
    AVG(ABS(a.zscore)) as avg_zscore
FROM anomalies a
GROUP BY a.tenant_id, a.detection_date, a.metric_name, a.severity;
