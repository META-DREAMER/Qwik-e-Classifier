
From: https://www.yoctoproject.org/docs/2.4.2/mega-manual/mega-manual.html

Install yocto dependencies:
```bash
$ sudo apt-get install gawk wget git-core diffstat unzip texinfo gcc-multilib \
     build-essential chrpath socat cpio python python3 python3-pip python3-pexpect \
     xz-utils debianutils iputils-ping libsdl1.2-dev xterm libssl-dev
```

Install `poky`
```bash
$ cd ~
$ git clone git://git.yoctoproject.org/poky
# checkout the latest release, in our case 2.4.2
$ cd poky
$ git checkout morty
```
?? last line

Clone the meta layers required for our board
```bash
# current directory is ~/poky, we want to clone in the folder `~/poky/meta-altera` by doing:
$ git clone https://github.com/altera-opensource/meta-altera.git
$ cd meta-altera
$ git tag
$ git checkout tags/rel_angstrom-v2016.12-yocto2.2_18.03.01_pr -b meta-altera-morty
$ cd ..
$ git clone -b morty git://git.linaro.org/openembedded/meta-linaro.git
```

Initialize build environment
```bash
$ source oe-init-build-env
```

Configure `bblayers.conf` to point to the downloaded meta layers.
[example]

Configure `conf/locl.conf` to be MACHINE="cyclone5", add the gccversion at end, and kernel version. Also switched to deb packages?
[example]

In `~/poky/build`
```bitbake virtual/bootloader```

my PATH had a path with parentheses in it and caused a step to fail. Removing paths with spaces and () from PATH fixed it.


Error out with QA issue. For some reason OpenSSL isn't getting linked, so modify this recipe:
```
nano ../meta-linaro/meta-linaro-toolchain/recipes-devtools/gcc/libgcc_linaro-5.2.bb
```
add:
```
TARGET_CC_ARCH += "${LDFLAGS}" 
```