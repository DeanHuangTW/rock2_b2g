#!/bin/bash

ME=$0

rm -rf  FirmwareInstall
mkdir 	FirmwareInstall
export  FW_INST_PATH=`pwd`/FirmwareInstall


check_args()
{
    while [ -n "$1" ]
    do
        name=$(echo $1 | awk -F '=' '{print $1}')
        value=$(echo $1 | awk -F '=' '{print $2}')
        if [ "${name}" = "wifi_module" ]; then
            if [ "${value}" = "" ]; then
                value="true"
            fi
        fi
        case "${name}" in
            wifi_module) wifi_module=${value};;
            kernel_path) kernel_path=${value};;
        *)
            echo #
            echo "$ME [wifi_module[=true|false]] [kernel_path=/my/path]"
            echo "        wifi_module: whether copmile wifi_module or not"
            echo "        kernel_path: path of kernel which will be compiled"
            echo #
            exit 1;;
        esac
        shift
    done
}

check_args $*

#default no TF/EMMC support now.
TF_EMMC_SUPPORT="yes"

#apks will be deleted completed.
DELETE_APKS="VideoEditor"

#apks will be moved to fs_patch/system/app folder so can be easy to delete or modify.
PATCH_SYS_APKS="Browser Calculator Calendar Contacts DeskClock DownloadProviderUi \
             Email Galaxy4 HoloSpiralWallpaper LatinIME WmtLauncher \
             MagicSmokeWallpapers MusicFX OpenWnn PinyinIME QuickSearchBox  \
             SpeechRecorder Exchange2 Phone LiveWallpapers LiveWallpapersPicker VisualizationWallpapers"

#apks will be moved to optional folder
OPTIONAL_APKS="SpareParts SelfTest WmtAirShare TVShell \
            OTAUpdateService OTAUpdateActivity \
            FMRadio Launcher2 Music WonderTV WmtSetupWizard"

if [ -z ${FW_INST_PATH} ];then
    echo "  No FW_INST_PATH defined!"
    exit 0
fi

if [ ! -d ${FW_INST_PATH} ];then
    echo "  ${FW_INST_PATH} is not a directory!"
    echo "  *W* you should config 'FW_INST_PATH' in your ENV,"
    echo "  and make sure you have put FW install package in the path"
    exit 1
fi

echo FW_INST_PATH=$FW_INST_PATH

android_dir=`pwd`
#kernel_dir is kernel path, for example: "../../../kernel/ANDROID_3.4.5/"
kernel_dir=$kernel_path
if [ ! -z "$kernel_path" ]; then
    echo "  Compile Kernel/Modules ..."
    stop_flg=0
    if [ -d $kernel_dir ];then
        cd $kernel_dir
        rm uzImage.bin
        rm modules.tgz
        ./modules_release.sh
        if [ $? -ne 0 ] ; then
            echo "  *W* Failed during excute modules_release.sh ! "
            stop_flg=1
        else
            if [ -f uzImage.bin ];then
                echo "  Copy new Kernel/Modules ..."
                cp -av uzImage.bin $android_dir/device/via/vixen/extra_packages/
                cp -av modules.tgz $android_dir/device/via/vixen/extra_packages/
            else
                echo "  *W* uzImage.bin not found! "
                stop_flg=1
            fi
        fi
        cd $android_dir
    else
        echo "  *W* Not found kernel path $kernel_dir "
        stop_flg=1
    fi

    if [ $stop_flg -ne 0 ] ; then
        echo "  *E* Failed to compile Kernel/Modules, exit!!"
        exit 1
    fi

    echo "  Compile Android ..."
    make -j4
    if [ $? -ne 0 ] ; then
        echo "  *E* Failed to compile android code, exit!!"
        exit 1
    fi
fi

if [ ! -z "$wifi_module" ] ; then
    echo "  Compile special WiFi module, by Kevin/Rubbit"
    make wifi
    if [ $? -ne 0 ] ; then
        echo "  *E* Failed to compile WiFi module, exit!!"
        exit 1
    fi
fi

OUT_DIR=$android_dir/out/target/product/vixen
TEMP_ROOTFS=/tmp/wmt_rootfs_temp_${RANDOM}

echo "  Prepare android base rootfs package"
rm -rf ${TEMP_ROOTFS}
mkdir -p ${TEMP_ROOTFS}

# copy /system and /data to temp folder.
cp -ar ${OUT_DIR}/system ${TEMP_ROOTFS}


##Delete all unused apks
found_apk=""
for i in $DELETE_APKS; do
    for path in system/app data/app system/vendor/app; do
        apk=`find ${TEMP_ROOTFS}/$path -iname ${i}.apk 2>/dev/null`
        if [ "$apk" != "" ]; then
            rm $apk
            found_apk+="$path/$i.apk "
            break
        fi
    done
done
echo "    Deleted APKs: $found_apk"


##Move all optional apks to optional folder.
mkdir -p ${FW_INST_PATH}/optional
found_apk=""
for i in $OPTIONAL_APKS; do
    for path in system/app data/app system/vendor/app; do
        apk=`find ${TEMP_ROOTFS}/$path -iname ${i}.apk 2>/dev/null`
        if [ "$apk" != "" ]; then
            mv $apk ${FW_INST_PATH}/optional
            found_apk+="$path/$i.apk "
            break
        fi
    done
done
echo "    Optional APKs: $found_apk"


#Move patch system apks to fs_patch/system/app/
mkdir -p ${FW_INST_PATH}/fs_patch/system/app/
for i in $PATCH_SYS_APKS; do
    if [ -f ${TEMP_ROOTFS}/system/app/$i.apk ]; then
        mv ${TEMP_ROOTFS}/system/app/$i.apk ${FW_INST_PATH}/fs_patch/system/app/
    fi
done

#Move WMT's apk to to fs_patch/system/vendor/app
mkdir -p ${FW_INST_PATH}/fs_patch/system/vendor/app
mv ${TEMP_ROOTFS}/system/vendor/app/*.apk ${FW_INST_PATH}/fs_patch/system/vendor/app/

#Bluetooth apk will be moved to bluetooth patch
mkdir -p ${FW_INST_PATH}/bluetooth/system/app/
mv ${TEMP_ROOTFS}/system/app/Bluetooth.* ${FW_INST_PATH}/bluetooth/system/app/
mkdir -p ${FW_INST_PATH}/bluetooth/system/etc/permissions/
cp ${android_dir}/frameworks/native/data/etc/android.hardware.bluetooth.xml ${FW_INST_PATH}/bluetooth/system/etc/permissions/


#move these apks to phone's patch
mkdir -p ${FW_INST_PATH}/phone/system/app/
mkdir -p ${FW_INST_PATH}/phone/system/etc/permissions/
mv ${TEMP_ROOTFS}/system/app/Mms.apk  ${FW_INST_PATH}/phone/system/app/
mv ${TEMP_ROOTFS}/system/app/SoundRecorder.apk  ${FW_INST_PATH}/phone/system/app/
if [ -f ${TEMP_ROOTFS}/system/app/Utk.apk ]; then
    mv ${TEMP_ROOTFS}/system/app/Utk.apk  ${FW_INST_PATH}/phone/system/app/
fi
cp ${android_dir}/frameworks/native/data/etc/android.hardware.telephony.cdma.xml ${FW_INST_PATH}/phone/system/etc/permissions/
cp ${android_dir}/frameworks/native/data/etc/android.hardware.telephony.gsm.xml  ${FW_INST_PATH}/phone/system/etc/permissions/


#move these files to iOS's patch
mkdir -p ${FW_INST_PATH}/ios_ui/system/app/
mkdir -p ${FW_INST_PATH}/ios_ui/system/framework/
mv ${TEMP_ROOTFS}/system/app/iLauncher.apk  ${FW_INST_PATH}/ios_ui/system/app/
mv ${TEMP_ROOTFS}/system/app/iSettings.apk  ${FW_INST_PATH}/ios_ui/system/app/
mv ${TEMP_ROOTFS}/system/app/iSystemUI.apk  ${FW_INST_PATH}/ios_ui/system/app/
mv ${TEMP_ROOTFS}/system/app/iGallery2.apk  ${FW_INST_PATH}/ios_ui/system/app/
mv ${TEMP_ROOTFS}/system/app/iLatinIME.apk  ${FW_INST_PATH}/ios_ui/system/app/
mv ${TEMP_ROOTFS}/system/app/iWmtMusic.apk  ${FW_INST_PATH}/ios_ui/system/app/

#remove Win8's apk
rm ${TEMP_ROOTFS}/system/app/SystemUI8.apk
rm ${TEMP_ROOTFS}/system/vendor/app/Charmbar.apk
rm ${TEMP_ROOTFS}/system/vendor/app/LockScreenWallpaper.apk
rm ${TEMP_ROOTFS}/system/vendor/app/MetroInstaller.apk

#move these files to nmi_tv patch
mkdir -p ${FW_INST_PATH}/nmi_tv/
mv ${TEMP_ROOTFS}/system/lib/libjniAtvDev.so  ${FW_INST_PATH}/nmi_tv/
mv ${TEMP_ROOTFS}/system/lib/libjniNtvDev.so  ${FW_INST_PATH}/nmi_tv/


#move following compnents to fs_patch/system
if [ -f ${TEMP_ROOTFS}/system/etc/cdrom.iso ]; then
    mkdir -p ${FW_INST_PATH}/fs_patch/system/etc/
    mv ${TEMP_ROOTFS}/system/etc/cdrom.iso ${FW_INST_PATH}/fs_patch/system/etc/
fi

echo "  remove those lines starting with '#' in default.prop ..."
cp -a ${TEMP_ROOTFS}/system/default.prop ${TEMP_ROOTFS}/system/temp
grep -E -v ^# ${TEMP_ROOTFS}/system/temp > ${TEMP_ROOTFS}/system/default.prop
rm ${TEMP_ROOTFS}/system/temp

echo -n "  Prepare android4.2.tar ..."
tar cf android4.2.tar -C ${TEMP_ROOTFS} .
echo -e "\b\b\bdone"


mkdir -p ${FW_INST_PATH}/firmware/
mv -v android4.2.tar ${FW_INST_PATH}/firmware/

if [ -f ${OUT_DIR}/Res_WmtLauncher.tgz ]; then
    cp -av ${OUT_DIR}/Res_WmtLauncher.tgz ${FW_INST_PATH}/firmware/
fi

if [ -f ${OUT_DIR}/Res_TVShell.tgz ]; then
    mkdir -p ${FW_INST_PATH}/TV/
    cp -av ${OUT_DIR}/Res_TVShell.tgz ${FW_INST_PATH}/TV
fi

#default 512M and Nand ramdisk
cp -av ${OUT_DIR}/ramdisk.img ${FW_INST_PATH}/firmware/
cp -av ${OUT_DIR}/ramdisk-recovery.img ${FW_INST_PATH}/firmware/

cp -av device/via/vixen/extra_packages/uzImage.bin ${FW_INST_PATH}/firmware/
cp -av device/via/vixen/extra_packages/modules.tgz ${FW_INST_PATH}/firmware/

#TODO: for 1024M DDR, should modify runinitscript.sh in sys_partition_end.sh

if [ "$TF_EMMC_SUPPORT" == "yes" ]; then
    current_path=`pwd`
    new_path="$current_path/rdisk"
    ramdisk_path="$new_path/new_ramdisk"

    #prepare TF/EMMC boot ramdisk
    rm -rf $ramdisk_path
    mkdir -p $ramdisk_path
    cp ${OUT_DIR}/ramdisk.img $new_path/ramdisk.gz
    gunzip $new_path/ramdisk.gz
    cd $ramdisk_path
    cpio -idm <$new_path/ramdisk
    sed -i 's/mount yaffs2 mtd@system \/system ro remount/mount ext4 \/dev\/block\/mmcblk1p2 \/system ro remount/g' init.rc
    sed -i 's/mount yaffs2 mtd@system \/system/wait \/dev\/block\/mmcblk1p2\n wait \/dev\/block\/mmcblk1p5\n wait \/dev\/block\/mmcblk1p7\n mount ext4 \/dev\/block\/mmcblk1p2 \/system/g' init.rc
    sed -i 's/mount yaffs2 mtd@data \/data nosuid nodev/mount ext4 \/dev\/block\/mmcblk1p7 \/data/g' init.rc
    sed -i 's/mount yaffs2 mtd@cache \/cache nosuid nodev/mount ext4 \/dev\/block\/mmcblk1p5 \/cache/g' init.rc
    rm $new_path/ramdisk
    find . | cpio -o -H newc | gzip > $new_path/ramdisk.gz
    cd $new_path
    mv $new_path/ramdisk.gz ${FW_INST_PATH}/firmware/ramdisk-TF.img
    cd $current_path

    #prepare TF/EMMC recovery ramdisk
    rm -rf $ramdisk_path
    mkdir -p $ramdisk_path
    cp ${OUT_DIR}/ramdisk-recovery.img $new_path/ramdisk-recovery.gz
    gunzip $new_path/ramdisk-recovery.gz
    cd $ramdisk_path
    cpio -idm <$new_path/ramdisk-recovery
    sed -i 's/yaffs2       system/ext4       \/dev\/block\/mmcblk1p2/g' etc/recovery.fstab
    sed -i 's/yaffs2       data/ext4       \/dev\/block\/mmcblk1p7/g' etc/recovery.fstab
    sed -i 's/yaffs2       cache/ext4       \/dev\/block\/mmcblk1p5/g' etc/recovery.fstab
    sed -i 's/mtd          misc/emmc       \/dev\/block\/mmcblk1p6/g' etc/recovery.fstab
    rm $new_path/ramdisk-recovery
    find . | cpio -o -H newc | gzip > $new_path/ramdisk-recovery.gz
    cd $new_path
    mv $new_path/ramdisk-recovery.gz ${FW_INST_PATH}/firmware/ramdisk-recovery-TF.img
    cd $current_path
fi

rm -rf ${TEMP_ROOTFS}

echo "All done!"
