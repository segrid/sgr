#!/bin/bash
#This script is using to prepare Azure Virtual Machine for publishing to marketplace

#Launch an ubuntu minimal machine as sgr-hub
#Connect to the machine via ssh and run following commands to create startup script
echo '#!/bin/bash' > /var/lib/cloud/scripts/per-boot/segrid-startup.sh
echo 'curl -fsSL https://raw.githubusercontent.com/segrid/sgr/main/install.sh -o install.sh' >> /var/lib/cloud/scripts/per-boot/segrid-startup.sh
echo 'export SEGRID_CLOUD_PROVIDER=azure' >> /var/lib/cloud/scripts/per-boot/segrid-startup.sh
echo 'sudo -E /bin/bash ./install.sh' >> /var/lib/cloud/scripts/per-boot/segrid-startup.sh
chmod 744 /var/lib/cloud/scripts/per-boot/segrid-startup.sh

