# dev-vm

Setup/installation scripts for a SWCombine development system

# Instructions

## VM Install

1. Download and install Oracle VirtualBox
2. Create a new virtual machine with an 8-10 GB drive
3. Download and install Debian 7.4 from the [net install CD](http://www.debian.org/CD/netinst/), follow the instructions. Host/domain are not important and can be whatever you like
4. Add yourself to the sudoers file:
```shell
$ su root
# visudo
Add the line "<your username> ALL=NOPASSWD: ALL" without <>
Ctrl+o to write
Ctrl+x to exit
# exit
```

## VM Config

1. Download the whole repository or just `swc_setup.sh`
2. Obtain a copy of `staging_prod.sql` from another dev (please don't distribute this to just anyone, for now)
3. Run `./swc_setup.sh` and follow the instructions

The results will look something like this:

![Sample script output](http://i.imgur.com/OXIEbzh.png)

## VM Tweaking

There are a lot of minor tweaks that may be desirable for you to have a more comfortable working environment.

1. Set up [shared folders](https://www.virtualbox.org/manual/ch04.html#sharedfolders) to have your code changes immediately visible on your dev VM while working outside of it with your existing IDE/tool setup.
2. Set up [port forwarding](https://www.virtualbox.org/manual/ch06.html#natforward) for port 80 and optionally port 22 for ssh, to access the VM site outside of your VM
3. Automount your shared folder (via /etc/fstab) and [run in headless mode](https://www.virtualbox.org/manual/ch07.html#vboxheadless) to save resources normally used to run the (unnecessary) VM GUI. You will need to forward port 22 if you wish to run headless, so you can shut down your VM later
