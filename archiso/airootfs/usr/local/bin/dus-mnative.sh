#!/bin/bash

arch=$(uname -m)

sudo sed -i "s/-march=$arch/-march=native/g" /etc/makepkg.conf
