## Download tools
Download linux source from: https://downloadcenter.intel.com/download/26687/Downloads-for-the-Terasic-DE10-Nano-Kit-Featuring-an-Intel-Cyclone-V-FPGA-SoC?v=t

Want the 1.8GB file.


Download OpenCL programs that run on the FPGA: http://dl.altera.com/?edition=standard
Navigate to "Additional Software" and download `Intel FPGA Runtime Environment for OpenCL Linux Cyclone V SoC TGZ`

## Extract Linux source
Extract from `sources\arm-angstrom-linux-gnueabi\linux-altera-ltsi-4.1.33\`

## Configure Linux kernel
Navigate to the folder containing the extracted kernel (Makefile is in the same level) and run: `make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-`

This will run a configuration wizard, I added support for Altera CPUs.

## Extract OpenCL FPGA executables
Extract folder and navigate to: `aocl-rte-17.1.0-590.arm32\board\c5soc\arm32\driver`

Run `make` to generate kernel driver