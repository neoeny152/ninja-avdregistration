# AVD Session Host Re-Registration PowerShell Script

A robust PowerShell script designed to automate the process of moving an Azure Virtual Desktop (AVD) session host to a new host pool, or re-registering an accidentally removed host back to its rightful host pool. This script is built to be run via an RMM tool (like NinjaOne, Datto, etc.) or locally with administrative privileges.

It handles the complete workflow: uninstalls the existing AVD agent, reinstalls the latest version with a new registration key, verifies the connection to the new host pool, and reboots the machine to finalize the changes.

---

## Use Cases

This script is ideal for two common administrative scenarios:

1.  **Moving a Session Host to a New Host Pool:** When you need to migrate an existing AVD session host from one host pool to another (e.g., moving from a "Testing" pool to a "Production" pool).
2.  **Re-registering a Corrupted or Removed Host:** If a session host was accidentally removed from its host pool in the Azure portal or its registration has become corrupted, this script can quickly and reliably re-establish its connection.

---

## ⚠️ Important Prerequisites

Before running this script, you **MUST** perform the following manual step:

* **Remove the Session Host from the Old Host Pool:** In the Azure Portal, navigate to the *original* host pool, select the session host(s) you intend to move, and remove them. The script cannot do this for you and will fail if the host is still associated with the old pool.

---

## 🚀 How to Use

1.  **Generate a New Registration Key:**
    * In the Azure Portal, navigate to the **target** (new) host pool.
    * Go to the **Overview** blade and click on **Registration key**.
    * A new key valid for a limited time will be generated. Copy this key.

2.  **Edit the Script:**
    * Open the `.ps1` script file in a text editor (like VS Code or PowerShell ISE).
    * Locate the `$RegistrationKey` variable near the top of the script.
    * Paste the key you just copied from the Azure Portal inside the double quotes.

    ```powershell
    # EXAMPLE:
    $RegistrationKey = "eyJhbGciOiJSUzI1NiIsImtpZCI6IjE..."
    ```

3.  **Run the Script:**
    * Execute the script on the target AVD session host with **Administrator privileges**.
    * You can run it manually or deploy it through your RMM platform.

The script will then run automatically, requiring no further interaction.

---

## ⚙️ How It Works

The script performs the following actions in sequence:

1.  **Logging:** Creates a transcript log file in `C:\admin` to record all actions and outcomes.
2.  **Safety Check:** Verifies that a registration key has been pasted into the `$RegistrationKey` variable before proceeding.
3.  **Uninstall Agent:** Searches for any existing installations of the "Remote Desktop Services Infrastructure Agent" and uninstalls them silently. It is designed to handle multiple or broken installations gracefully.
4.  **Download Agent:** Downloads the latest version of the AVD agent installer directly from Microsoft's official URL.
5.  **Reinstall & Re-register:** Runs the installer silently, passing in the new registration key to connect the host to the new pool.
6.  **Verify:** Pauses for 60 seconds to allow the agent to start, then checks the Windows Event Log (`Microsoft-Windows-RemoteDesktopServices-RdaAgent/Admin`) for **Event ID 3701**, which confirms a successful connection to the AVD broker. It will log success or failure based on this check.
7.  **Cleanup:** Deletes the downloaded installer and rotates log files, keeping only the five most recent logs.
8.  **Reboot:** Forces a reboot of the machine to ensure all changes are applied correctly.

---

## 📄 Logging and Verification

* **Log Location:** `C:\admin\AVD_Re-Registration_YYYY-MM-DD_HH-mm-ss.log`
* **Successful Run:** The log file will show a "VERIFICATION SUCCESS" message containing the details of Event ID 3701. After the reboot, the session host should appear as "Available" in the new host pool in the Azure Portal.
* **Failed Run:** If the script encounters an error, it will be logged in the transcript. Check the event log for specific AVD agent error messages that can help diagnose the issue (e.g., networking problems, invalid key).
