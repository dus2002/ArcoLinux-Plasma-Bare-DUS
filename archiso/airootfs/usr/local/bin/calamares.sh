#!/bin/bash

systemctl disable calamares
rm /etc/systemd/system/calamares.service
rm -Rf /etc/calamaresmod
rm -Rf /etc/calamares
rm /usr/local/bin/calamares.sh
