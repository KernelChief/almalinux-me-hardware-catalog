# AlmaLinux M&E SIG: "Works On" Hardware Survey

This tool helps the **AlmaLinux Media & Entertainment (M&E) SIG** track hardware compatibility for professional creative workflows. By contributing, you help the community validate which workstations and components are "production-ready" for VFX, Animation, and Video Production.

---

## 🛡️ Privacy & Transparency

**Does this script send data automatically?** **No.** The script generates a local `almalinux_me_report.json` file. You have full control; you must manually review the file and choose to share it.

**What is being collected?** * **Hardware:** CPU, GPU, and Motherboard models; RAM quantity and speeds.  
* **Software:** Kernel and Driver versions currently in use.  
* **Feedback:** Your specific notes on performance or bugs.  

**What is NOT being collected?** * **No Serial Numbers:** We omit hardware UUIDs and serial numbers.  
* **No Network Info:** No IP or MAC addresses are gathered.  
* **No Personal Files:** We do not scan your home directory or personal data.  

### 📦 Prerequisites
The script may prompt to install the following (if not present) to ensure accurate reporting:
* `pciutils`: To identify PCIe devices.
* `lshw`: To identify vendors and manufacturers.
* `dmidecode`: To read system/BIOS information.

---

## 🛠️ How to Run

You can run the script using this one-liner:

`curl -sSL https://raw.githubusercontent.com/AlmaLinux/me-sig-workson/main/almalinux_me_report.sh | bash`

**Or step-by-step:**
1. **Download:** `curl -O https://raw.githubusercontent.com/AlmaLinux/me-sig-workson/main/almalinux_me_report.sh`
2. **Make executable:** `chmod +x almalinux_me_report.sh`
3. **Run:** `./almalinux_me_report.sh`

---

## 📤 How to Submit

Once the script finishes, it will generate a file named `almalinux_me_report.json` and a unique **Report ID**.

1. **Copy** the contents of `almalinux_me_report.json`.
2. **Open a [New Issue](https://github.com/AlmaLinux/me-sig-workson/issues/new)** on this repository.
3. **Title:** Use your **Report ID** (e.g., `Report ID: a1b2c3d4`).
4. **Content:** Paste the JSON data into the issue description.

---
*Thank you for helping build a more stable ecosystem for the AlmaLinux M&E community!*