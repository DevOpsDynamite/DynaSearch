# Lynis Hardening Guide for Azure Ubuntu 24.04 VM

## Introduction

This document outlines the steps taken to harden an Azure Ubuntu 24.04 LTS Virtual Machine based on the findings of a `lynis audit system` scan (run on 2025-05-05, using Lynis version 3.0.9, achieving an initial hardening index of 66). The goal is to address key suggestions provided by Lynis to improve the overall security posture of the VM.

**Environment:**
* **Cloud Provider:** Microsoft Azure
* **Operating System:** Ubuntu 24.04 LTS
* **Lynis Version (Initial):** 3.0.9

**Prerequisites & Cautions:**
* **Backups:** Always ensure a recent VM snapshot or backup exists in Azure before applying configuration changes.
* **Testing:** Thoroughly test system functionality and SSH access after each significant change.
* **Understanding:** Do not apply changes blindly. Understand the purpose and potential impact of each command.
* **SSH Access:** Be extremely careful when modifying SSH configurations (`/etc/ssh/sshd_config`). Test connectivity with a *new* terminal session before closing the current one. Use Azure Serial Console for recovery if needed.

---

## Remediation Steps

### 1. Update Lynis

* **Suggestion ID:** `[LYNIS]`
* **Reason:** The installed Lynis version (3.0.9) was outdated. Newer versions contain updated tests, fixes, and improved detection capabilities.
* **Steps Taken:**
    ```bash
    # Navigate to a suitable location for source code
    cd /usr/local/src

    # Clone the latest version from GitHub (or use 'git pull' if already cloned)
    git clone [https://github.com/CISOfy/lynis.git](https://github.com/CISOfy/lynis.git)
    cd lynis

    # Optional: Link the new version for easier access system-wide
    # sudo ln -sf /usr/local/src/lynis/lynis /usr/local/bin/lynis
    ```
* **Verification:** Run `lynis show version` (adjust path if not linked) to confirm the updated version.

### 2. Install Recommended Debian/Ubuntu Packages

* **Suggestion IDs:** `[DEB-0280]`, `[DEB-0810]`, `[DEB-0811]`, `[PKGS-7370]`, `[PKGS-7394]`
* **Reason:** Install utility packages recommended by Lynis to enhance security insights during package management and verify package integrity.
    * `libpam-tmpdir`: Set temporary directories correctly for PAM sessions.
    * `apt-listbugs`: Show critical bugs before installing/upgrading packages.
    * `apt-listchanges`: Show changelogs before upgrades.
    * `debsums`: Verify installed package file integrity using MD5 sums.
    * `apt-show-versions`: Assist with patch management tracking.
* **Steps Taken:**
    ```bash
    sudo apt update
    sudo apt install apt-listbugs apt-listchanges debsums apt-show-versions libpam-tmpdir -y
    ```
* **Verification:** Re-run `lynis audit system`. The corresponding suggestions should no longer appear. `apt-listbugs` and `apt-listchanges` will activate during future `apt upgrade` commands.

### 3. Set GRUB Boot Loader Password

* **Suggestion ID:** `[BOOT-5122]`
* **Reason:** Protect the GRUB bootloader configuration from unauthorized modification via console access (physical or Azure Serial Console), preventing actions like bypassing security by booting into single-user mode.
* **Steps Taken:**
    1.  Generate a PBKDF2 password hash for GRUB:
        ```bash
        grub-mkpasswd-pbkdf2
        # Enter a strong password twice and copy the output hash string
        ```
    2.  Create a custom GRUB configuration file for the password:
        ```bash
        sudo nano /etc/grub.d/01_PASSWORD
        ```
    3.  Add the following content, replacing `YOUR_GENERATED_PASSWORD_HASH` with the copied hash:
        ```bash
        #!/bin/sh
        cat << EOF
        set superusers="root"
        password_pbkdf2 root YOUR_GENERATED_PASSWORD_HASH
        EOF
        ```
    4.  Set appropriate permissions:
        ```bash
        sudo chmod 750 /etc/grub.d/01_PASSWORD
        ```
    5.  Update the main GRUB configuration:
        ```bash
        sudo update-grub
        ```
* **Verification:** Reboot the VM. Attempting to edit a boot entry (press 'e' at the GRUB menu) should now prompt for the configured username (`root`) and password. Re-run Lynis.

### 4. Harden SSH Configuration

* **Suggestion IDs:** `[SSH-7408]` (multiple settings)
* **Reason:** Reduce the attack surface of the SSH daemon (sshd), a critical network entry point.
* **Steps Taken:**
    1.  **Backup** the existing configuration:
        ```bash
        sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak_$(date +%F)
        ```
    2.  **Edit** the configuration file:
        ```bash
        sudo nano /etc/ssh/sshd_config
        ```
    3.  Applied the following changes (ensure values are uncommented or added):
        * `AllowTcpForwarding no` (Disables SSH tunneling)
        * `ClientAliveCountMax 2` (Reduces idle timeout duration)
        * `LogLevel VERBOSE` (Increases log detail)
        * `MaxAuthTries 3` (Limits password attempts per connection)
        * `MaxSessions 2` (Limits concurrent sessions per connection)
        * `TCPKeepAlive no` (Relies on ClientAlive settings instead)
        * `X11Forwarding no` (Disables GUI forwarding)
        * `AllowAgentForwarding no` (Disables agent forwarding)
        * *(Optional but Recommended)* `PasswordAuthentication no` (If using SSH keys exclusively)
        * *(Optional, High Impact)* Changed `Port 22` to `Port <CustomPort>` (Requires Azure NSG update, see Azure Notes)
    4.  **Test** the configuration syntax:
        ```bash
        sudo sshd -t
        ```
    5.  **Restart** the SSH service:
        ```bash
        sudo systemctl restart sshd
        ```
* **Verification:** Immediately attempt to log in via SSH in a **new terminal window** to confirm access. Test with the new port if changed (`ssh user@host -p <CustomPort>`). Re-run Lynis; the addressed `[SSH-7408]` suggestions should be resolved.

### 5. Harden Kernel Parameters (sysctl)

* **Suggestion ID:** `[KRNL-6000]`
* **Reason:** Tune kernel runtime parameters for improved security based on Lynis profile recommendations.
* **Steps Taken:**
    1.  Created a custom sysctl configuration file:
        ```bash
        sudo nano /etc/sysctl.d/60-lynis-hardening.conf
        ```
    2.  Added the following recommended settings (based on 'DIFFERENT' findings in the initial report):
        ```ini
        # Prevent non-root users loading TTY line disciplines
        dev.tty.ldisc_autoload = 0
        # Protect FIFO files (named pipes)
        fs.protected_fifos = 2
        # Set core dump SUID behavior
        fs.suid_dumpable = 0
        # Append PID to core filenames
        kernel.core_uses_pid = 1
        # Restrict access to kernel pointers via /proc
        kernel.kptr_restrict = 2
        # Set Perf event paranoia level
        kernel.perf_event_paranoid = 3
        # Disable SysRq key completely
        kernel.sysrq = 0
        # Disable unprivileged BPF access
        kernel.unprivileged_bpf_disabled = 1
        # Harden BPF JIT compiler
        net.core.bpf_jit_harden = 2
        # Disable IP forwarding (if not a router)
        net.ipv4.conf.all.forwarding = 0
        net.ipv6.conf.all.forwarding = 0
        # Log Martian packets (impossible source addresses)
        net.ipv4.conf.all.log_martians = 1
        net.ipv4.conf.default.log_martians = 1
        # Enable Reverse Path Filtering (anti-spoofing)
        net.ipv4.conf.all.rp_filter = 1
        # Do not send ICMP redirects
        net.ipv4.conf.all.send_redirects = 0
        # Do not accept source-routed packets
        net.ipv4.conf.default.accept_source_route = 0
        ```
        *Note:* `kernel.modules_disabled=1` was skipped due to potential impact on functionality requiring module loading after boot.
    3.  Applied the changes without rebooting:
        ```bash
        sudo sysctl --system
        ```
* **Verification:** Check individual keys using `sudo sysctl <key>` (e.g., `sudo sysctl fs.protected_fifos`). Re-run Lynis; the `[KRNL-6000]` suggestion should reflect the changes or disappear if all profile mismatches are resolved.

### 6. Add Legal Banners

* **Suggestion IDs:** `[BANN-7126]`, `[BANN-7130]`
* **Reason:** Display warning/policy banners to users before login (local console and SSH) to deter unauthorized access and meet potential compliance requirements.
* **Steps Taken:**
    1.  Edited the local login banner file (`/etc/issue`):
        ```bash
        sudo nano /etc/issue
        ```
        Replaced content with a standard authorized access warning. OS info (`\S`, `\l`) can optionally be kept.
    2.  Edited the remote login banner file (`/etc/issue.net`):
        ```bash
        sudo nano /etc/issue.net
        ```
        Added a similar authorized access warning. **Removed any OS-specific info tags.**
    3.  Ensured SSH uses the banner by checking `/etc/ssh/sshd_config` for an active `Banner /etc/issue.net` line. Restarted `sshd` if changes were needed.
* **Verification:** Check the banner appearance on the Azure Serial Console (`/etc/issue`) and during the SSH prompt before password/key entry (`/etc/issue.net`). Re-run Lynis.

### 7. Install Audit Daemon (auditd)

* **Suggestion ID:** `[ACCT-9628]`
* **Reason:** Enable detailed system auditing capabilities to log security-relevant events for monitoring, forensics, and compliance.
* **Steps Taken:**
    1.  Installed `auditd` and plugins:
        ```bash
        sudo apt update
        sudo apt install auditd audispd-plugins -y
        ```
    2.  Enabled and started the service:
        ```bash
        sudo systemctl enable auditd
        sudo systemctl start auditd
        ```
    3.  *(Initial Configuration)* Added basic rules for logins to `/etc/audit/rules.d/10-logins.rules` (Further rule sets based on CIS/STIG or specific policies are recommended).
    4.  Loaded the rules:
        ```bash
        sudo augenrules --load
        ```
* **Verification:** Check service status (`sudo systemctl status auditd`). Examine logs using `ausearch` or `aureport`. Re-run Lynis.

### 8. Install File Integrity Monitor (AIDE)

* **Suggestion ID:** `[FINT-4350]`
* **Reason:** Implement a tool to detect unauthorized modifications to critical system files.
* **Steps Taken:**
    1.  Installed AIDE:
        ```bash
        sudo apt update
        sudo apt install aide aide-common -y
        ```
    2.  Initialized the AIDE database (baseline):
        ```bash
        # Run configuration, which triggers DB build
        sudo aideinit
        # Copy the newly generated DB to be the active reference DB
        sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
        ```
    3.  Configured daily checks via cron (default setup in `/etc/cron.daily/aide`).
* **Verification:** Run a manual check (`sudo aide --check`). After intentional system changes (e.g., package updates), update the database (`sudo aide --update` followed by reviewing and replacing `aide.db`). Re-run Lynis.

---

## Azure Specific Considerations

* **Network Security Groups (NSGs):** Firewall rules applied within the VM (like `ufw` or `iptables`) are separate from Azure NSGs. Any changes to service ports (e.g., SSH) or enabling new network services require corresponding **Allow** rules in the VM's NSG configured via the Azure Portal. Consider restricting access to specific source IPs in NSG rules.
* **Secure Boot:** Lynis noted Secure Boot was disabled (`[BOOT-5116]`). This is common for Azure Linux VMs. Enabling it might require specific Azure image generations and could complicate boot/driver processes. The risk was accepted for this environment.
* **USB Storage:** Disabling USB storage drivers (`[USB-1000]`) is less critical in Azure VMs but can be done as a minor hardening step if desired by blacklisting the `usb-storage` module.
* **Systemd Service Hardening:** Lynis flagged many services as `UNSAFE` (`[BOOT-5264]`). Further hardening involves editing systemd unit files to add security options (`PrivateTmp`, `ProtectSystem`, etc.). This requires per-service analysis and was deferred for later consideration, including investigating specific Azure agent services (`azuremonitor-*`).

---

## General Recommendations

* **Re-run Lynis:** Periodically run `sudo lynis audit system` to assess the current hardening score and identify new issues or regressions.
* **Prioritize:** Continue addressing remaining Lynis suggestions based on risk and relevance to the VM's role.
* **Monitor Logs:** Regularly check system logs (`/var/log/syslog`, `/var/log/auth.log`) and audit logs (`/var/log/audit/audit.log` or via `ausearch`/`aureport`) for suspicious activity.
* **Patch Management:** Keep the system updated using `sudo apt update && sudo apt upgrade`. Review changes proposed by `apt-listchanges` and `apt-listbugs`.