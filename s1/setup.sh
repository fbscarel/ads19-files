#!/usr/bin/env bash

mv /home/vagrant/scripts/* /usr/local/bin
rm -r /home/vagrant/scripts

chown root. /usr/local/bin/*
chmod +x /usr/local/bin/*
