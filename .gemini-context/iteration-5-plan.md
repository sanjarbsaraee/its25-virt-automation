# Iteration 5 Plan: Monitoring and Advanced Hardening

This plan outlines the deployment of the monitoring stack (Prometheus, Grafana, Alertmanager) and advanced database auditing (`pgAudit`), incorporating the optimizations discussed for security, automation, and live demonstration.

## 1. Objectives
*   Deploy a dedicated monitoring node (`monitor-01`).
*   Implement centralized metrics collection and alerting.
*   Enable advanced database auditing on the PostgreSQL node.
*   Route all monitoring UI traffic securely through the existing load balancer.
*   Ensure all components are verified automatically.

## 2. Design Decisions and Rationale
These adjustments have been added to the baseline plan to improve security, reliability, and presentation flow:

*   **Grafana via Load Balancer:** Grafana traffic will be routed through the existing Load Balancer instead of exposing port 3000 directly. 
    *   *Why:* To maintain the security posture established in Iteration 4 (least privilege) and handle access control in one central place.
    *   *Note:* We must configure Grafana's `root_url` to include the `/grafana` subpath, otherwise its internal links for CSS and JS will break.
*   **Prometheus Ansible Collection:** We will use the `prometheus.prometheus` collection instead of the Debian Apt package.
    *   *Why:* Debian stable packages are often outdated. The official collection provides the latest features, better security defaults, and a standardized layout.
*   **Goss Binary Checksum:** A SHA-256 checksum will be included in the `get_url` task for downloading Goss.
    *   *Why:* To ensure supply chain integrity and prevent execution of corrupted or maliciously modified binaries.
*   **Expanded pgAudit Logging:** The `pgaudit.log` setting will be set to `'ddl, write'`.
    *   *Why:* To ensure the actual audit trail covers structural database changes, making the code match the security claims made in the project presentation.
*   **Alertmanager API Verification:** The verification script will query the REST API at `localhost:9093/api/v2/alerts`.
    *   *Why:* To enable fully automated, non-interactive testing and remove the need for a human to manually inspect the UI.
*   **Demo-Friendly Alert Timing:** The `for` parameter in `alert_rules.yml` will be reduced to `15s` or `30s`.
    *   *Why:* To prevent awkward 2-minute delays during the live demonstration while waiting for the CPU alert to trigger.

## 3. Proposed Changes

### Infrastructure (Terraform)
*   **[NEW]** Provision `monitor-01` VM with IP `192.168.50.250`.
*   Update Proxmox firewall rules to allow node exporter traffic to `monitor-01`.

### Ansible Automation
*   Apply the `prometheus.prometheus` collection to `monitor-01`.
*   Configure Nginx on `lb-01` to reverse proxy `/grafana` to `monitor-01:3000`.
*   Configure Grafana's `root_url` setting to support the `/grafana` subpath.
*   Install `pgAudit` on `db-01` and apply the `'ddl, write'` configuration.

## 4. Verification Plan
*   **Automated:** Run `./scripts/verify-iter5.sh` to check UFW rules, port isolation, and verify that Alertmanager detects the simulated high load via API.
*   **Manual:** Access Grafana via `http://<lb-ip>/grafana` and verify the dashboard is receiving data.

## 5. Estimated Effort and Feasibility
These additions represent minimal extra work and focus on best practices:
*   **Saves Time:** The Prometheus collection eliminates the need to write custom systemd services and user creation tasks.
*   **Trivial Edits:** Checksums, pgAudit settings, and alert timings are single-line configuration changes.
*   **Low Effort:** Routing Grafana requires only a few lines in the existing Nginx template and setting one variable in the Grafana config.
