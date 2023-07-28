#!/bin/bash
echo '#!/bin/bash' > /var/lib/cloud/scripts/per-boot/segrid-startup.sh
echo 'curl -fsSL https://raw.githubusercontent.com/segrid/sgr/main/install.sh -o install.sh' >> /var/lib/cloud/scripts/per-boot/segrid-startup.sh
echo 'export CLOUD_PROVIDER=azure' >> /var/lib/cloud/scripts/per-boot/segrid-startup.sh
echo 'sudo -E /bin/bash ./install.sh' >> /var/lib/cloud/scripts/per-boot/segrid-startup.sh
chmod 744 /var/lib/cloud/scripts/per-boot/segrid-startup.sh