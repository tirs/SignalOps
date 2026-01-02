-- SignalOps Database Schema - Anomaly Detection (MySQL)
-- Migration: 004_add_anomalies.sql
-- Description: Anomaly detection results and incident management

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

-- Incidents table (promoted from anomalies)
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

-- Incident status history
CREATE TABLE IF NOT EXISTS incident_status_history (
    id VARCHAR(36) PRIMARY KEY,
    incident_id VARCHAR(36),
    user_id VARCHAR(36),
    old_status ENUM('open', 'investigating', 'mitigated', 'closed', 'false_positive'),
    new_status ENUM('open', 'investigating', 'mitigated', 'closed', 'false_positive') NOT NULL,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (incident_id) REFERENCES incidents(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Anomaly baselines (pre-computed for performance)
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

-- Trigger to log incident status changes
DELIMITER //
CREATE TRIGGER incident_status_change_trigger
AFTER UPDATE ON incidents
FOR EACH ROW
BEGIN
    IF OLD.status <> NEW.status THEN
        INSERT INTO incident_status_history (id, incident_id, old_status, new_status)
        VALUES (UUID(), NEW.id, OLD.status, NEW.status);
    END IF;
END//
DELIMITER ;

-- View for incident dashboard
CREATE OR REPLACE VIEW incident_dashboard AS
SELECT 
    i.id,
    i.title,
    i.status,
    i.severity,
    i.created_at,
    i.sla_due_at,
    CASE 
        WHEN i.sla_due_at < NOW() AND i.status NOT IN ('closed', 'false_positive') 
        THEN TRUE 
        ELSE FALSE 
    END as sla_breached,
    TIMESTAMPDIFF(HOUR, i.created_at, NOW()) as age_hours,
    u_assigned.email as assigned_to_email,
    CONCAT(u_assigned.first_name, ' ', u_assigned.last_name) as assigned_to_name,
    u_created.email as created_by_email,
    (SELECT COUNT(*) FROM incident_comments ic WHERE ic.incident_id = i.id) as comment_count
FROM incidents i
LEFT JOIN users u_assigned ON i.assigned_to = u_assigned.id
LEFT JOIN users u_created ON i.created_by = u_created.id;

-- View for anomaly summary
CREATE OR REPLACE VIEW anomaly_summary AS
SELECT 
    a.tenant_id,
    a.detection_date,
    a.metric_name,
    a.severity,
    COUNT(*) as anomaly_count,
    AVG(ABS(a.zscore)) as avg_zscore
FROM anomalies a
GROUP BY a.tenant_id, a.detection_date, a.metric_name, a.severity;

-- Schema migrations tracking table
CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(100) PRIMARY KEY,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
