#!/bin/sh -e
#
# Copyright (c) 2014-2016 Robert Nelson <robertcnelson@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

export LC_ALL=C

#contains: rfs_username, release_date
if [ -f /etc/rcn-ee.conf ] ; then
	. /etc/rcn-ee.conf
fi

if [ -f /etc/oib.project ] ; then
	. /etc/oib.project
fi

export HOME=/home/${rfs_username}
export USER=${rfs_username}
export USERNAME=${rfs_username}

echo "env: [`env`]"

is_this_qemu () {
	unset warn_qemu_will_fail
	if [ -f /usr/bin/qemu-arm-static ] ; then
		warn_qemu_will_fail=1
	fi
}

qemu_warning () {
	if [ "${warn_qemu_will_fail}" ] ; then
		echo "Log: (chroot) Warning, qemu can fail here... (run on real armv7l hardware for production images)"
		echo "Log: (chroot): [${qemu_command}]"
	fi
}

git_clone () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone ${git_repo} ${git_target_dir} --depth 1 || true"
	qemu_warning
	git clone ${git_repo} ${git_target_dir} --depth 1 || true
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

git_clone_branch () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone -b ${git_branch} ${git_repo} ${git_target_dir} --depth 1 || true"
	qemu_warning
	git clone -b ${git_branch} ${git_repo} ${git_target_dir} --depth 1 || true
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

git_clone_full () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone ${git_repo} ${git_target_dir} || true"
	qemu_warning
	git clone ${git_repo} ${git_target_dir} || true
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

wget_and_untar () {
    wget -qO- ${src_url} | tar xvz -C ${target_dir}
    echo "${target_dir} : ${src_url}" >> /opt/source/list.txt
}

setup_system () {
	echo "" >> /etc/securetty
	echo "#USB Gadget Serial Port" >> /etc/securetty
	echo "ttyGS0" >> /etc/securetty
}

install_redeem_deb_pkgs () {

    echo "Log: (umikaze): installing redeem lib dependencies"
	apt-get update
	echo "APT::Install-Recommends \"false\";" > /etc/apt/apt.conf.d/99local
	echo "APT::Install-Suggests \"false\";" >> /etc/apt/apt.conf.d/99local
	apt-get install --no-install-recommends -y \
	python-pip \
	python-setuptools \
	python-dev \
	swig \
	socat \
	ti-pru-cgt-installer
}

install_redeem_src_pkgs () {
    echo "Log: (umikaze): pru support"
    src_url="http://git.ti.com/pru-software-support-package/pru-software-support-package/archive-tarball/v5.1.0"
    target_dir="/usr/src/"
    wget_and_untar
    mv /usr/src/pru-software-support-package-pru-software-support-package /usr/src/pru-software-support-package

    echo "Log: (umikaze): am335x pru support"
	wget https://github.com/beagleboard/am335x_pru_package/archive/master.zip
	unzip master.zip

    echo "Log: (umikaze): pasm compiler"
	# install pasm PRU compiler
	mkdir /usr/include/pruss
	cd am335x_pru_package-master/
	cp pru_sw/app_loader/include/prussdrv.h /usr/include/pruss/
	cp pru_sw/app_loader/include/pruss_intc_mapping.h /usr/include/pruss

	chmod 555 /usr/include/pruss/*
	cd pru_sw/app_loader/interface

    echo "Log: (umikaze): cross compile"
	CROSS_COMPILE= make
	cp ../lib/* /usr/lib

    echo "Log: (umikaze): ldconfig, source and install"
	ldconfig
	cd ../../utils/pasm_source/
	source linuxbuild
	cp ../pasm /usr/bin/
	chmod +x /usr/bin/pasm
}

install_redeem_pip_pkgs () {
    echo "Log: (umikaze): installing redeem pip packages"
    pip install numpy evdev spidev Adafruit_BBIO sympy
}

install_redeem () {
    install_redeem_deb_pkgs
    install_redeem_src_pkgs
    install_redeem_pip_pkgs

    echo "Log: (umikaze): installing redeem"
    cd /usr/src/
	if [ ! -d "redeem" ]; then
		git clone --no-single-branch --depth 1 https://github.com/intelligent-agent/redeem.git
	fi
	cd redeem
	git pull
    git checkout develop
	make install

	# Make profiles uploadable via Octoprint
	cp -r configs /etc/redeem
	cp -r data /etc/redeem
	touch /etc/redeem/local.cfg
}

install_git_repos () {
	git_repo="https://github.com/strahlex/BBIOConfig.git"
	git_target_dir="/opt/source/BBIOConfig"
	git_clone

	git_repo="https://github.com/RobertCNelson/dtb-rebuilder.git"
	git_target_dir="/opt/source/dtb-4.4-ti"
	git_branch="4.4-ti"
	git_clone_branch

	git_repo="https://github.com/RobertCNelson/dtb-rebuilder.git"
	git_target_dir="/opt/source/dtb-4.9-ti"
	git_branch="4.9-ti"
	git_clone_branch

	git_repo="https://github.com/beagleboard/bb.org-overlays"
	git_target_dir="/opt/source/bb.org-overlays"
	git_clone
}

configure_cpufrequtils () {
	echo "GOVERNOR=\"performance\"" > /etc/default/cpufrequtils
	systemctl stop ondemand
	systemctl disable ondemand
}

install_replicape_dts () {

	echo "Log: (umikaze) install replicape overlays"
	git_repo="https://github.com/ThatWileyGuy/bb.org-overlays"
	git_target_dir="/usr/src/bb.org-overlays"
	git_clone

	cd /usr/src/bb.org-overlays
	./dtc-overlay.sh # upgrade DTC version!
	./install.sh

	for kernel in `ls /lib/modules`; do update-initramfs -u -k $kernel; done

}

install_nmtui () {

	echo "Log: (umikaze) disable wireless power management"
	mkdir -p /etc/pm/sleep.d
	touch /etc/pm/sleep.d/wireless

	echo "Log: (umikaze) install network manager"
	apt-get -y install --no-install-recommends network-manager
	#ln -s /run/resolvconf/resolv.conf /etc/resolv.conf
	sed -i 's/^\[main\]/\[main\]\ndhcp=internal/' /etc/NetworkManager/NetworkManager.conf
	cp $WD/interfaces /etc/network/

}

cleanup() {
	echo "Log: (umikaze) cleanup"*
	rm -rf /etc/apache2/sites-enabled
	rm -rf /root/.c9
	rm -rf /usr/local/lib/node_modules
	rm -rf /var/lib/cloud9
	rm -rf /usr/lib/node_modules/
	apt-get purge -y apache2 apache2-bin apache2-data apache2-utils hostapd connman
}


is_this_qemu

setup_system

if [ -f /usr/bin/git ] ; then
	git config --global user.email "${rfs_username}@example.com"
	git config --global user.name "${rfs_username}"
	install_git_repos
	git config --global --unset-all user.email
	git config --global --unset-all user.name
fi

install_redeem
configure_cpufrequtils
install_replicape_dts


apt-get autoremove -y

