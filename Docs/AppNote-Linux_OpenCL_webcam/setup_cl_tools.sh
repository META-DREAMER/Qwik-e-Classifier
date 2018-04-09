#!/bin/bash

# copy the files needed for the `clinfo` command to work
cd ~
mkdir -p /etc/OpenCL/vendors
cp ~/aocl-rte-17.1.0-590.arm32/Altera.icd /etc/OpenCL/vendors 

mkdir -p /opt/Intel/OpenCL/Boards
echo /home/root/aocl-rte-17.1.0-590.arm32/board/c5soc/arm32/lib/libintel_soc32_mmd.so > /opt/Intel/OpenCL/Boards/c5.fcd

# install clinfo (a diagnostic program), OpenCL headers, and nano
sudo apt install clinfo ocl-icd-opencl-dev nano