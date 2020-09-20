#!/bin/sh

mv /home/vagrant/scripts/* /usr/local/bin
rm -f /home/vagrant/scripts

chown root. /usr/local/bin/*.sh
chmod +x /usr/local/bin/*.sh
