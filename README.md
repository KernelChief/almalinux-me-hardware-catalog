# AlmaLinux M&E Hardware Survey

A fast, friendly way to share **hardware compatibility reports** for AlmaLinux M&E workflows. Your report helps the community identify which workstations and parts are reliable for VFX, Animation, and Video Production.

---

## 🛡️ Privacy & Transparency

**Does this script send data automatically?** **No.** The script generates local files and you choose whether to share them.

**What is being collected?** 
* **Hardware:** CPU and GPU models, RAM total and module info (if available), storage controllers.  
* **Software:** Kernel, OS release, platform.  
* **Feedback:** Your notes on performance, bugs, or success stories.  

**What is NOT being collected?**
* **No serial numbers or hardware UUIDs.**  
* **No network details** (IP/MAC).  
* **No personal files** or home directory scans.  

### 📦 Prerequisites
The script checks for required commands and will tell you what to install if needed:
* `pciutils`: To identify PCIe devices.
* `dmidecode`: To read system/BIOS information.

---

## 🛠️ How to Run

Run the script with this one-liner:

`curl -sSL https://raw.githubusercontent.com/KernelChief/almalinux-me-hardware-catalog/main/scripts/almalinux-me-hardware-survey-reporter.sh | bash`

**Or step-by-step:**
1. **Download:** `curl -O https://raw.githubusercontent.com/KernelChief/almalinux-me-hardware-catalog/main/scripts/almalinux-me-hardware-survey-reporter.sh`
2. **Make executable:** `chmod +x almalinux-me-hardware-survey-reporter.sh`
3. **Run:** `./almalinux-me-hardware-survey-reporter.sh`

Security note: the one-liner runs a remote script immediately. If you prefer, download it first and review the file before running.

---

## 📤 How to Submit

Once the script finishes, it will generate:
* `almalinux_me_report.json` (your data)
* a **Report ID** (stable on your machine, not based on serials)

**Submit manually (easy):**
1. Open the issue form:  
   https://github.com/KernelChief/almalinux-me-hardware-catalog/issues/new?template=hardware_report.yml
2. Title the issue with your **Report ID** (example: `7e66c449`).
3. Paste the full contents of `almalinux_me_report.json` into the JSON field.

Tip: You can view the JSON with:
`cat almalinux_me_report.json`

## ❓ FAQ

**Do I need a GitHub account to submit?**  
Yes. Submissions are done through a GitHub issue form.

**Will this script upload anything automatically?**  
No. It only writes local files. You decide whether to submit.

**What if I run it twice?**  
The **Report ID stays the same** on that machine, so duplicates are easy to spot.

**How do I reset my Report ID?**  
Delete this file and re-run the script:  
`~/.config/almalinux-me-hardware-survey/report_id`

**Does it collect serial numbers or UUIDs?**  
No. The script explicitly avoids serials and hardware UUIDs.

**Why is it asking for sudo or dmidecode?**  
`dmidecode` reads memory module details and often needs elevated access. If it fails, the report still works.

**I got a “missing command” error. What do I do?**  
Install the suggested package(s) from the script output and re-run.

**Can I edit my report before submitting?**  
Yes. Open `almalinux_me_report.json` in a text editor and remove anything you do not want to share.

**The repo is private. Will the website still publish?**  
GitHub Pages does not publish from private repos on free plans. You can still collect data and submit reports; publishing can be enabled later.

**How does approval work?**  
When a maintainer adds the `approved` label to your issue, a GitHub Action automatically generates a Markdown page and opens a PR for review.

## 🧰 Maintainer Guide

**Approve a submission**
1. Open the issue and confirm it includes valid JSON in the “JSON Data” field.
2. Add the `approved` label to the issue.
3. A GitHub Action will generate `data/reports/<id>.json` and `docs/results/<id>/index.md`, then open a PR.
4. The action comments on the issue with the PR link.
5. Review the PR and merge when ready.
6. When the PR is merged, a second action closes the issue automatically.

**Reject or request changes**
- If the JSON is incomplete or sensitive, comment on the issue and remove the `approved` label (if present).

**Publish the website**
- GitHub Pages only publishes from public repos on free plans.
- Once public (or on a paid plan), merges to `main` will trigger the MkDocs deploy action.

## 📄 License

This project is licensed under the GNU GPLv3. See `LICENSE`.

---
Thank you for helping build a more stable AlmaLinux M&E ecosystem.
