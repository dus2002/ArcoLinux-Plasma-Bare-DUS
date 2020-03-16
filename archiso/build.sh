#!/bin/bash

set -e -u

iso_name="arcolinux-plasma-bare-dus"
iso_version="v20.3.1"
iso_label="al-plasma-bare-dus-${iso_version}"
iso_publisher="ArcoLinux <http://www.arcolinux.info>"
iso_application="ArcoLinux Live/Rescue CD"
install_dir=arch
work_dir=work
out_dir=out
gpg_key=
verbose=""
script_path=$(readlink -f ${0%/*})
arch=$(ls $script_path/packages* | cut -d "." -f2)
linux=$(ls $script_path/.linux* | cut -d "." -f2)





umask 0022

_usage ()
{
    echo "usage ${0} [options]"
    echo
    echo " General options:"
    echo "    -N <iso_name>      Set an iso filename (prefix)"
    echo "                        Default: ${iso_name}"
    echo "    -V <iso_version>   Set an iso version (in filename)"
    echo "                        Default: ${iso_version}"
    echo "    -L <iso_label>     Set an iso label (disk label)"
    echo "                        Default: ${iso_label}"
    echo "    -P <publisher>     Set a publisher for the disk"
    echo "                        Default: '${iso_publisher}'"
    echo "    -A <application>   Set an application name for the disk"
    echo "                        Default: '${iso_application}'"
    echo "    -D <install_dir>   Set an install_dir (directory inside iso)"
    echo "                        Default: ${install_dir}"
    echo "    -w <work_dir>      Set the working directory"
    echo "                        Default: ${work_dir}"
    echo "    -o <out_dir>       Set the output directory"
    echo "                        Default: ${out_dir}"
    echo "    -v                 Enable verbose output"
    echo "    -h                 This help message"
    exit ${1}
}

# Helper function to run make_*() only one time per architecture.
run_once() {
    if [[ ! -e ${work_dir}/build.${1} ]]; then
        $1
        touch ${work_dir}/build.${1}
    fi
}
echo "###################################################################"
tput setaf 3;echo "0. start of the build script";tput sgr0
echo "###################################################################"




# Setup custom pacman.conf with current cache directories.
make_pacman_conf() {
    echo "###################################################################"
    tput setaf 3;echo "1. Create base SO and set variables";tput sgr0
    echo "###################################################################"
    local _cache_dirs
    _cache_dirs=($(pacman -v 2>&1 | grep '^Cache Dirs:' | sed 's/Cache Dirs:\s*//g'))
    sed -r "s|^#?\\s*CacheDir.+|CacheDir = $(echo -n ${_cache_dirs[@]})|g" ${script_path}/pacman.conf > ${work_dir}/pacman.conf
    mkarchiso ${verbose} -w "${work_dir}/$arch" -C "${work_dir}/pacman.conf" -D "${install_dir}" init
    cp ${script_path}/mkinitcpio-airootfs.conf ${work_dir}/$arch/airootfs/etc/mkinitcpio.conf
    #cp -af ${script_path}/airootfs/root/customize_airootfs.sh ${work_dir}/$arch/root/customized_installation.sh
    #for $arch in $(cat ${script_path}/arch) do
         #echo "Patching files to install using $arch"
         #cat ${work_dir}/$arch/root/customized_installation.sh | sed -i "s/defaultarch/$arch/g" > ${work_dir}/$arch/root/customized_installation.sh
         #sed -r "s|^#?\\s*CacheDir.+|CacheDir = $(echo -n ${_cache_dirs[@]})|g" ${script_path}/$arch/pacman.conf > ${work_dir}/pacman.conf
         #iso_label="al-plasma-bare-dus-${iso_version}-$arch"
    #done
}

# Base installation, plus needed packages (airootfs)
make_basefs() {
    echo "###################################################################"
    tput setaf 3;echo "2. Install kernel";tput sgr0
    echo "###################################################################"
    mkarchiso ${verbose} -w "${work_dir}/$arch" -C "${work_dir}/pacman.conf" -D "${install_dir}" -p "$linux-broadcom-wl $linux $linux-headers" install
    linuxnumber=$(echo $linux | cut -d "x" -f2 | sed 's/./&./1')
    kernelversion=$(ls $work_dir/$arch/lib/modules | cut -f9 | sed '$d')
}

# Additional packages (airootfs)
make_packages() {
    echo "###################################################################"
    tput setaf 3;echo "3. Additional packages (airootfs)";tput sgr0
    echo "###################################################################"
    mkarchiso ${verbose} -w "${work_dir}/$arch" -C "${work_dir}/pacman.conf" -D "${install_dir}" -p "$(grep -h -v ^# ${script_path}/packages.$arch)" install
}

# Copy mkinitcpio archiso hooks and build initramfs (airootfs)
make_setup_mkinitcpio() {
    echo "###################################################################"
    tput setaf 3;echo "5. Copy mkinitcpio archiso hooks and build initramfs (airootfs)";tput sgr0
    echo "###################################################################"
    local _hook
    mkdir -p ${work_dir}/$arch/airootfs/etc/initcpio/hooks
    mkdir -p ${work_dir}/$arch/airootfs/etc/initcpio/install
    for _hook in archiso archiso_shutdown archiso_loop_mnt; do
        cp /usr/lib/initcpio/hooks/${_hook} ${work_dir}/$arch/airootfs/etc/initcpio/hooks
        cp /usr/lib/initcpio/install/${_hook} ${work_dir}/$arch/airootfs/etc/initcpio/install
    done
    sed -i "s|/usr/lib/initcpio/|/etc/initcpio/|g" ${work_dir}/$arch/airootfs/etc/initcpio/install/archiso_shutdown
    cp /usr/lib/initcpio/install/archiso_kms ${work_dir}/$arch/airootfs/etc/initcpio/install
    cp /usr/lib/initcpio/archiso_shutdown ${work_dir}/$arch/airootfs/etc/initcpio
    cp ${script_path}/mkinitcpio.conf ${work_dir}/$arch/airootfs/etc/mkinitcpio-archiso.conf
    gnupg_fd=
    if [[ ${gpg_key} ]]; then
      gpg --export ${gpg_key} >${work_dir}/gpgkey
      exec 17<>${work_dir}/gpgkey
    fi
    ARCHISO_GNUPG_FD=${gpg_key:+17} mkarchiso ${verbose} -w "${work_dir}/$arch" -C "${work_dir}/pacman.conf" -D "${install_dir}" -r "mkinitcpio -c /etc/mkinitcpio-archiso.conf -k /boot/vmlinuz-$linuxnumber-$arch -g /boot/archiso.img" run
    if [[ ${gpg_key} ]]; then
      exec 17<&-
    fi
}

# Customize installation (airootfs)
make_customize_airootfs() {
    echo "###################################################################"
    tput setaf 3;echo "4. Customize installation (airootfs)";tput sgr0
    echo "###################################################################"
    
    cp -af ${script_path}/airootfs/* ${work_dir}/$arch/airootfs

    cp ${script_path}/pacman.conf.work_dir ${work_dir}/$arch/airootfs/etc/pacman.conf


    #lynx -dump -nolist 'https://wiki.archlinux.org/index.php/Installation_Guide?action=render' >> ${work_dir}/$arch/airootfs/root/install.txt

    mkarchiso ${verbose} -w "${work_dir}/$arch" -C "${work_dir}/pacman.conf" -D "${install_dir}" -r "/root/customize/customize_airootfs-$arch.sh" run
    rm -R ${work_dir}/$arch/airootfs/root/customize
}

# Prepare kernel/initramfs ${install_dir}/boot/
make_boot() {
    echo "###################################################################"
    tput setaf 3;echo "6. Prepare kernel/initramfs ${install_dir}/boot/";tput sgr0
    echo "###################################################################"
    mkdir -p ${work_dir}/iso/${install_dir}/boot/$arch
    cp ${work_dir}/$arch/airootfs/boot/archiso.img ${work_dir}/iso/${install_dir}/boot/$arch/archiso.img
    cp ${work_dir}/$arch/airootfs/boot/vmlinuz-$linuxnumber-$arch ${work_dir}/iso/${install_dir}/boot/$arch/vmlinuz
}

# Add other aditional/extra files to ${install_dir}/boot/
make_boot_extra() {
    echo "###################################################################"
    tput setaf 3;echo "7. Add other aditional/extra files to ${install_dir}/boot/";tput sgr0
    echo "###################################################################"
    cp ${work_dir}/$arch/airootfs/boot/intel-ucode.img ${work_dir}/iso/${install_dir}/boot/intel_ucode.img
    cp ${work_dir}/$arch/airootfs/usr/share/licenses/intel-ucode/LICENSE ${work_dir}/iso/${install_dir}/boot/intel_ucode.LICENSE
    cp ${work_dir}/$arch/airootfs/boot/amd-ucode.img ${work_dir}/iso/${install_dir}/boot/amd_ucode.img
    cp ${work_dir}/$arch/airootfs/usr/share/licenses/amd-ucode/LICENSE ${work_dir}/iso/${install_dir}/boot/amd_ucode.LICENSE
}

# Prepare /${install_dir}/boot/syslinux
make_syslinux() {
    echo "###################################################################"
    tput setaf 3;echo "8. Prepare /${install_dir}/boot/syslinux";tput sgr0
    echo "###################################################################"
    mkdir -p ${work_dir}/iso/${install_dir}/boot/syslinux
    for _cfg in ${script_path}/syslinux/*.cfg; do
        sed "s|%ARCHISO_LABEL%|${iso_label}|g;
             s|%INSTALL_DIR%|${install_dir}|g" ${_cfg} > ${work_dir}/iso/${install_dir}/boot/syslinux/${_cfg##*/}
    done
    cp ${script_path}/syslinux/splash.png ${work_dir}/iso/${install_dir}/boot/syslinux
    cp ${work_dir}/$arch/airootfs/usr/lib/syslinux/bios/*.c32 ${work_dir}/iso/${install_dir}/boot/syslinux
    cp ${work_dir}/$arch/airootfs/usr/lib/syslinux/bios/lpxelinux.0 ${work_dir}/iso/${install_dir}/boot/syslinux
    cp ${work_dir}/$arch/airootfs/usr/lib/syslinux/bios/memdisk ${work_dir}/iso/${install_dir}/boot/syslinux
    mkdir -p ${work_dir}/iso/${install_dir}/boot/syslinux/hdt
    gzip -c -9 ${work_dir}/$arch/airootfs/usr/share/hwdata/pci.ids > ${work_dir}/iso/${install_dir}/boot/syslinux/hdt/pciids.gz
    gzip -c -9 ${work_dir}/$arch/airootfs/usr/lib/modules/*/modules.alias > ${work_dir}/iso/${install_dir}/boot/syslinux/hdt/modalias.gz
}

# Prepare /isolinux
make_isolinux() {
    echo "###################################################################"
    tput setaf 3;echo "9. Prepare /isolinux";tput sgr0
    echo "###################################################################"
    mkdir -p ${work_dir}/iso/isolinux
    sed "s|%INSTALL_DIR%|${install_dir}|g" ${script_path}/isolinux/isolinux.cfg > ${work_dir}/iso/isolinux/isolinux.cfg
    cp ${work_dir}/$arch/airootfs/usr/lib/syslinux/bios/isolinux.bin ${work_dir}/iso/isolinux/
    cp ${work_dir}/$arch/airootfs/usr/lib/syslinux/bios/isohdpfx.bin ${work_dir}/iso/isolinux/
    cp ${work_dir}/$arch/airootfs/usr/lib/syslinux/bios/ldlinux.c32 ${work_dir}/iso/isolinux/
}

# Build airootfs filesystem image
make_prepare() {
    echo "###################################################################"
    tput setaf 3;echo "10. Build airootfs filesystem image";tput sgr0
    echo "###################################################################"
	mv ${work_dir}/$arch/airootfs/boot/vmlinuz* ${work_dir}/$arch/airootfs/boot/vmlinuz-$linuxnumber-$arch
    cp -a -l -f ${work_dir}/$arch/airootfs ${work_dir}
    mkarchiso ${verbose} -w "${work_dir}" -D "${install_dir}" pkglist
    mkarchiso -c zstd ${verbose} -w "${work_dir}" -D "${install_dir}" ${gpg_key:+-g ${gpg_key}} prepare
    # rm -rf ${work_dir}/$arch/airootfs (if low space, this helps)
}

# Build ISO
make_iso() {
    echo "###################################################################"
    tput setaf 3;echo "11. Build ISO";tput sgr0
    echo "###################################################################"
    mkarchiso ${verbose} -w "${work_dir}" -D "${install_dir}" -L "${iso_label}" -P "${iso_publisher}" -A "${iso_application}" -o "${out_dir}" iso "${iso_name}-${iso_version}.iso"
}

# checks and sign
make_checks() {
    echo "###################################################################"
    tput setaf 3;echo "14. checks and sign";tput sgr0
    echo "###################################################################"
    echo "Building sha1sum"
    echo "########################"
    cd ${out_dir}
    sha1sum ${iso_label}.iso > ${iso_label}.sha1
    echo "Building sha256sum"
    echo "########################"
    sha256sum ${iso_label}.iso > ${iso_label}.sha256
    echo "Building md5sum"
    echo "########################"
    md5sum ${iso_label}.iso > ${iso_label}.md5
    echo "Moving pkglist.$arch.txt"
    echo "########################"
    cd ..
    cp ${work_dir}/iso/arch/pkglist.$arch.txt  ${out_dir}/${iso_label}.iso.pkglist.txt
}


if [[ ${EUID} -ne 0 ]]; then
    echo "This script must be run as root."
    _usage 1
fi

while getopts 'N:V:L:P:A:D:w:o:g:vh' arg; do
    case "${arg}" in
        N) iso_name="${OPTARG}" ;;
        V) iso_version="${OPTARG}" ;;
        L) iso_label="${OPTARG}" ;;
        P) iso_publisher="${OPTARG}" ;;
        A) iso_application="${OPTARG}" ;;
        D) install_dir="${OPTARG}" ;;
        w) work_dir="${OPTARG}" ;;
        o) out_dir="${OPTARG}" ;;
        g) gpg_key="${OPTARG}" ;;
        v) verbose="-v" ;;
        h) _usage 0 ;;
        *)
           echo "Invalid argument '${arg}'"
           _usage 1
           ;;
    esac
done

mkdir -p ${work_dir}

run_once make_pacman_conf
run_once make_basefs
run_once make_packages
run_once make_customize_airootfs
run_once make_setup_mkinitcpio
run_once make_boot
run_once make_boot_extra
run_once make_syslinux
run_once make_isolinux
run_once make_prepare
run_once make_iso
