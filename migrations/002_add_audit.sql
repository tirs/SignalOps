-- SignalOps Database Schema - Audit Trail
-- Migration: 002_add_audit.sql
-- Description: Comprehensive audit logging for all critical actions

-- Audit action types
CREATE TYPE audit_action AS ENUM (
    'login',
    'logout',
    'login_failed',
    'password_change',
    'password_reset',
    'user_create',
    'user_update',
    'user_delete',
    'role_change',
    'data_import',
    'data_delete',
    'incident_create',
    'incident_update',
    'incident_assign',
    'incident_close',
    'comment_add',
    'report_generate',
    'settings_change',
    'export_data'
);

-- Audit log table
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    session_id UUID REFERENCES sessions(id) ON DELETE SET NULL,
    action audit_action NOT NULL,
    entity_type VARCHAR(100),
    entity_id UUID,
    old_values JSONB,
    new_values JSONB,
    ip_address VARCHAR(45),
    user_agent TEXT,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create index for efficient querying
CREATE INDEX idx_audit_tenant ON audit_logs(tenant_id);
CREATE INDEX idx_audit_user ON audit_logs(user_id);
CREATE INDEX idx_audit_action ON audit_logs(action);
CREATE INDEX idx_audit_entity ON audit_logs(entity_type, entity_id);
CREATE INDEX idx_audit_created ON audit_logs(created_at DESC);

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply updated_at trigger to relevant tables
CREATE TRIGGER update_tenants_updated_at
    BEFORE UPDATE ON tenants
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_metrics_updated_at
    BEFORE UPDATE ON metrics_data
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_validation_rules_updated_at
    BEFORE UPDATE ON validation_rules
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- View for user activity summary
CREATE VIEW user_activity_summary AS
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
