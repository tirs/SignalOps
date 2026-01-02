-- SignalOps Database Schema - Audit Trail (MySQL)
-- Migration: 002_add_audit.sql
-- Description: Comprehensive audit logging for all critical actions

-- Audit log table
CREATE TABLE IF NOT EXISTS audit_logs (
    id VARCHAR(36) PRIMARY KEY,
    tenant_id VARCHAR(36),
    user_id VARCHAR(36),
    session_id VARCHAR(36),
    action ENUM('login', 'logout', 'login_failed', 'password_change', 'password_reset',
                'user_create', 'user_update', 'user_delete', 'role_change',
                'data_import', 'data_delete', 'incident_create', 'incident_update',
                'incident_assign', 'incident_close', 'comment_add', 'report_generate',
                'settings_change', 'export_data') NOT NULL,
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

-- Create indexes for efficient querying
CREATE INDEX idx_audit_tenant ON audit_logs(tenant_id);
CREATE INDEX idx_audit_user ON audit_logs(user_id);
CREATE INDEX idx_audit_action ON audit_logs(action);
CREATE INDEX idx_audit_entity ON audit_logs(entity_type, entity_id);
CREATE INDEX idx_audit_created ON audit_logs(created_at DESC);

-- View for user activity summary
CREATE OR REPLACE VIEW user_activity_summary AS
SELECT 
    u.id as user_id,
    u.email,
    u.first_name,
    u.last_name,
    u.role,
    COUNT(CASE WHEN al.action = 'login' THEN 1 END) as login_count,
    MAX(CASE WHEN al.action = 'login' THEN al.created_at END) as last_login,
    COUNT(al.id) as total_actions
FROM users u
LEFT JOIN audit_logs al ON u.id = al.user_id
GROUP BY u.id, u.email, u.first_name, u.last_name, u.role;
