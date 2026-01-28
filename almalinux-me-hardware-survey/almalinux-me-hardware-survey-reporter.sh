#!/bin/bash

# AlmaLinux M&E Hardware Reporting Script v1.3
OUTPUT_FILE="almalinux_me_report.json"
REPORT_ID=$(echo "$HOSTNAME-$(date +%s)-$RANDOM" | md5sum | head -c 8)

echo "Checking dependencies..."
for pkg in pciutils lshw dmidecode; do
    if ! rpm -q $pkg > /dev/null; then
        sudo dnf install -y $pkg
    fi
done

echo "-------------------------------------------------------"
echo "AlmaLinux M&E Hardware Reporting Tool [$REPORT_ID]"
echo "-------------------------------------------------------"
read -p "Any notes (bugs, performance, 'all good')?: " USER_NOTES

json_escape() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' | sed 's/^"//;s/"$//'
}

if [ -f /etc/almalinux-release ]; then
    OS_NAME=$(cat /etc/almalinux-release)
elif [ -f /etc/redhat-release ]; then
    OS_NAME=$(cat /etc/redhat-release)
else
    OS_NAME=$(grep "PRETTY_NAME" /etc/os-release | cut -d= -f2 | tr -d '"')
fi

mem_info=$(sudo dmidecode -t 17 2>/dev/null | awk '
    /Size: [0-9]/ { s=$2" "$3 }
    /Speed: [0-9]/ { sp=$2" "$3 }
    /Manufacturer:/ { m=$2 }
    /Configured Memory Speed: [0-9]/ { cs=$4" "$5 }
    /Locator:/ {
        if(s!="") {
            if(found) printf ",\n";
            printf "    {\"size\": \"%s\", \"speed\": \"%s\", \"configured_speed\": \"%s\", \"manufacturer\": \"%s\"}", s, sp, cs, m;
            found=1; s=""; sp=""; cs=""; m="";
        }
    }
')

gpu_json=""
while read -r line; do
    slot=$(echo "$line" | cut -d' ' -f1)
    name=$(echo "$line" | cut -d: -f3- | xargs)
    driver=$(lspci -nnk -s "$slot" | grep "Kernel driver in use" | cut -d: -f2 | xargs)
    [ -n "$gpu_json" ] && gpu_json="$gpu_json,"
    gpu_json="$gpu_json {\"device\": \"$(json_escape "$name")\", \"driver\": \"$driver\"}"
done < <(lspci | grep -E "VGA|3D|Display")

cat <<EOF > $OUTPUT_FILE
{
  "report_id": "$REPORT_ID",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "user_notes": "$(json_escape "$USER_NOTES")",
  "system": {
    "os_release": "$OS_NAME",
    "kernel": "$(uname -r)",
    "platform": "$(uname -m)"
  },
  "processor": {
    "model": "$(grep -m 1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)",
    "cores": "$(nproc)"
  },
  "memory": {
    "total_gb": "$(free -g | awk '/^Mem:/{print $2}')",
    "modules": [ $mem_info ]
  },
  "graphics": [ $gpu_json ],
  "storage_controllers": [
$(lspci | grep -i "storage" | awk -F ': ' '{print "    {\"device\": \"" $2 "\"}"}' | paste -sd "," -)
  ]
}
EOF

echo "-------------------------------------------------------"
echo "DONE! Report ID: $REPORT_ID"
echo "File saved to: $OUTPUT_FILE"
echo "-------------------------------------------------------"
echo "SUBMISSION INSTRUCTIONS:"
echo "1. Go to: https://github.com/AlmaLinux/me-sig-workson/issues/new"
echo "2. Select 'Hardware Compatibility Report'"
echo "3. Use [$REPORT_ID] as the Report ID"
echo "4. Paste the content of $OUTPUT_FILE into the JSON field."
echo "-------------------------------------------------------"