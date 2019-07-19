#!/bin/sh

DEVICE="$1"
DEVICE_NAME=`echo "$DEVICE" |awk -F "/" '{print $NF}'`
P_PATH=""
P_DEVICE=""
IS_USE_NBD="false"
Parted_resize_result="failed"

LOG_LEVEL="null" # (null,debug)
LOG_OUTPUT="cmd" # (file,cmd)
LOG_FILE="/tmp/extend_${DEVICE_NAME}.log"
UUID="_uuid"

RESIZE_STATUS="fail"

genuuid(){
	uuidgenbin="`which uuidgen 2>/dev/null`"
	if [ "$LOG_LEVEL"x = "debug"x ] && [ -n "$uuidgenbin" ] ;then
		UUID="`uuidgen -r | awk -F '-' '{print $1}'`"
		UUID="_$UUID"
		LOG_FILE="/tmp/extend_${DEVICE_NAME}${UUID}.log"
		log "uuid:$UUID"
	fi
}

resize_fs(){
    echo "resize_fs call"
    get_map_partition
    log "P_PATH:$P_PATH"
	log "`ls -l $P_PATH`"
	if [ -L $P_PATH ];then
		 oldpath=$P_PATH
		 P_PATH=`readlink -f $P_PATH`
		 log "$oldpath is link file, update to $P_PATH by readlink"
	fi
	if [ -n "$P_PATH" ] && [ -b "$P_PATH" ];then
        if [ "$p_fstype"x = "xfs"x ];then
                resize_xfs
        elif [ "$p_fstype"x = "ext2"x ] || [ "$p_fstype"x = "ext3"x ] || [ "$p_fstype"x = "ext4"x ];then
                resize_extx
        elif [ "$p_fstype"x = "ntfs"x ];then
                resize_ntfs
        else
        	log "not support file system ${p_fstype}, resize fs failed!!!"
        	return
        fi
    else
    	log "can not get ${DEVICE} partition device,resize fs failed!!!" 	
    fi
    kpartx_unmap_partition
}

resize_ntfs(){
	log "resize_ntfs call"
	ntfsfixbin="`which ntfsfix 2>/dev/null`"
	ntfsresizebin="`which ntfsresize 2>/dev/null`"
	if [ -n "$ntfsfixbin" -a -n "$ntfsresizebin" ];then
		log "========="
		log "$ntfsfixbin -bd $P_PATH"
		$ntfsfixbin -bd $P_PATH
		log "+++++++++++++++++"
		log "$ntfsresizebin -f $P_PATH"
		$ntfsresizebin -f $P_PATH
		log "+++++++++++++++++"
		log "$ntfsfixbin -bd $P_PATH"
		$ntfsfixbin -bd $P_PATH
		log "========="
		RESIZE_STATUS="success"
	else
		log "can not find ntfsfix or ntfsresize, resize fs failed!!!"
	fi
}

resize_extx(){
	e2fsckbin="`which e2fsck 2>/dev/null`"
	resize2fsbin="`which resize2fs 2>/dev/null`"
	if [ -n "$e2fsckbin" -a -n "$resize2fsbin" ];then
		log "========="
		log "e2fsck -pf $P_PATH"
		$e2fsckbin -pf $P_PATH
		log "+++++++++++++++++"
		log "$resize2fsbin -f  $P_PATH"
		$resize2fsbin -f  $P_PATH
		log "+++++++++++++++++"
		log "e2fsck -pf $P_PATH"
		$e2fsckbin -pf $P_PATH
		log "========="
		RESIZE_STATUS="success"
	else
		log "can not find e2fsck or resize2fs , resize fs failed!!!"
	fi
}


resize_xfs(){
	log "resize_xfs call"
	xfsgrowfsbin="`which xfs_growfs 2>/dev/null`"
	if [ -n "$xfsgrowfsbin" ];then
		get_xfs_mnt_dir
		mkdir $p_xfs_mnt_path
		P_PATH_NAME=`echo "$P_PATH" |awk -F "/" '{print $NF}'`
		mount_result_file="/tmp/${P_PATH_NAME}_mount_result"
		mount -t xfs $P_PATH $p_xfs_mnt_path 2>$mount_result_file
		mount_result="`cat $mount_result_file`"
		if [ -n "$mount_result" ];then
			log "mount partition fail. device:$P_PATH path:$p_xfs_mnt_path reason:$mount_result"
			return
		else
			log "mount partition success. device:$P_PATH path:$p_xfs_mnt_path"
		fi
		#log "ls $p_xfs_mnt_path:`ls $p_xfs_mnt_path`"
		log "$xfsgrowfsbin $p_xfs_mnt_path result:"
		$xfsgrowfsbin $p_xfs_mnt_path
		#log "ls $p_xfs_mnt_path:`ls $p_xfs_mnt_path`"
		RESIZE_STATUS="success"
		umount_result_file="/tmp/${P_PATH_NAME}_umount_result"
		umount $p_xfs_mnt_path 2>$umount_result_file
		umount_result="`cat $umount_result_file`"
		if [ -z "$umount_result" ];then
			log "umount partition success. device:$P_PATH path:$p_xfs_mnt_path"
			rm -rf $p_xfs_mnt_path
		else
			log "umount partition failed. device:$P_PATH path:$p_xfs_mnt_path reason:$umount_result"
		fi
		
	else
		log "can not find xfs_growfs , resize fs failed!!!"
	fi
	
}

get_xfs_mnt_dir(){
	log "get_xfs_mnt_dir call"
	i=1
	p_xfs_mnt_prefix="/tmp/cloud_resize_xfs_tmp_dir_"
	while [ -d "${p_xfs_mnt_prefix}$i" ];do
		log "mntpath:${p_xfs_mnt_prefix}$i already used!"
		i=`expr $i + 1`
	done
	p_xfs_mnt_path="${p_xfs_mnt_prefix}$i"
	log "p_xfs_mnt_path:$p_xfs_mnt_path"
}

get_partition_device(){

	log "$DEVICE is a block device"
	#blockdev
	#partprobe
	blockdevbin="`which blockdev 2>/dev/null`"
	partprobebin="`which partprobe 2>/dev/null`"
	if [ -n "$blockdevbin" ];then
		log "$blockdevbin --rereadpt $DEVICE"
		$blockdevbin --rereadpt $DEVICE
	elif [ -n "$partprobebin" ];then
		log "$partprobebin $DEVICE"
		$partprobebin $DEVICE
	fi
	partition_total_num="`lsblk -p -n -o KNAME $DEVICE | wc -l`"
	if [ $partition_total_num -ge 2 ];then
		P_PATH="`lsblk -p -n -o KNAME $DEVICE | sort | tail -1`"
		P_DEVICE=$P_PATH
		log "get $DEVICE block device partition $P_DEVICE for resizefs"
	else
		log "can not load $DEVICE partition"
		return
	fi

}

get_map_partition(){
	log "get_map_partition call"
	if [ -b $DEVICE ];then
		get_partition_device
	else
		kpartx_map_partition
	fi
}

load_nbd(){
	log "load_nbd call"
	load_nbd_result="fail"
	modprobe_nbd_error_log="/tmp/modprobe_nbd_error_log${UUID}"
	modprobe nbd max_part=63 nbds_max=64 2>$modprobe_nbd_error_log
	modprobe_nbd_error_info="`cat $modprobe_nbd_error_log`"
	if [ -n "$modprobe_nbd_error_info" ];then
		log "can not load nbd kernel model error:$modprobe_nbd_error_info. "
		return 
	fi
	
	nbd_max_part="`cat /sys/module/nbd/parameters/max_part`"
	if [ $nbd_max_part -eq 0 ];then
		log "nbd max_part=0 . reload nbd"
		modprobe_r_nbd_error_log="/tmp/modprobe_r_nbd_error_log${UUID}"
		modprobe -r nbd 2>$modprobe_r_nbd_error_log
		modprobe_r_nbd_error_info="`cat $modprobe_r_nbd_error_log`"
		if [ -n "$modprobe_r_nbd_error_info" ];then
			log "can not reload nbd. remove nbd error:$modprobe_r_nbd_error_info"
			return
		else 
			log "remove nbd success"
			modprobe nbd max_part=63 nbds_max=64 2>$modprobe_nbd_error_log
			modprobe_nbd_error_info="`cat $modprobe_nbd_error_log`"
			if [ -n "$modprobe_nbd_error_info" ];then
				log "can not load nbd kernel model error:$modprobe_nbd_error_info. "
				return 
			else
				log "reload nbd success."
			fi
		fi
	fi
	log "load nbd success"
	load_nbd_result="success"
	
}

find_idle_nbd(){
	log "find_idle_nbd call"
	idle_nbd=""
	i=0
	nbd_status="`cat /sys/class/block/nbd${i}/trace/enable 2>/dev/null`"
	while [ -n "$nbd_status" ] && [ $nbd_status -eq 0 ] && [ $i -le 63 ];do
		log "nbd${i} already used"
		i=`expr $i + 1`
	done
	if [ -z "$nbd_status" ] && [ $i -le 63 ];then
		log "find idle nbd:nbd${i}"
		idle_nbd="/dev/nbd${i}"
	fi
	
}

attach_nbd(){
	log "attach_nbd call"
	find_idle_nbd
	if [ -z "$idle_nbd" ];then
		log "can not find idle_nbd. do nothing!"
		return
	fi
	idle_nbd_name=`echo $idle_nbd |awk -F "/" '{print $NF}'`
	qemu_nbd_attach_error_log="/tmp/${idle_nbd_name}_attach_error_info${UUID}"
	qemu-nbd -c $idle_nbd $DEVICE -f qcow2 2>$qemu_nbd_attach_error_log
	qemu_nbd_attach_error_info="`cat $qemu_nbd_attach_error_log`"
	if [ -n "$qemu_nbd_attach_error_info" ];then
		log "qemu-nbd -c $idle_nbd $DEVICE -f qcow2 fail. set DEVICE=null Error:$qemu_nbd_attach_error_info"
		DEVICE=""
		return
	else
		log "qemu-nbd -c $idle_nbd $DEVICE -f qcow2 success. update  DEVICE $DEVICE=>$idle_nbd"
		DEVICE=$idle_nbd
	fi
}

detach_nbd(){
	if [ -z "$idle_nbd" ];then
		log "idle_nbd is null. do nothing!"
		return
	fi
	qemu_nbd_detach_error_log="/tmp/${idle_nbd_name}_detach_error_info${UUID}"
	qemu-nbd -d $idle_nbd 2>$qemu_nbd_detach_error_log
	qemu_nbd_detach_error_info="`cat $qemu_nbd_detach_error_log`"
	if [ -n "$qemu_nbd_detach_error_info" ];then
		log "qemu-nbd -d $idle_nbd fail. Error:$qemu_nbd_detach_error_info"
	else
		log "qemu-nbd -d $idle_nbd success. "
	fi
	
}

# nobody call this funtion
kpartx_map_partition(){
	kpartxbin="`which kpartx 2>/dev/null`"
	if [ -n "$kpartxbin" ];then
		kpartxinfo="`$kpartxbin -av $DEVICE | sort |tail -1`"
		sleep 2
		log "kpartxinfo_av:$kpartxinfo"
		kpartxinfo_second="`echo $kpartxinfo| awk -F ' ' '{print $2}'`"
		if [ "$kpartxinfo_second"x = "map"x ];then
			kpartxinfo_map_name="`echo $kpartxinfo| awk -F ' ' '{print $3}'`"
			P_PATH="/dev/mapper/${kpartxinfo_map_name}"
			P_DEVICE="`echo $kpartxinfo| awk -F ' ' '{print $8}'`"
			log "kpartx get $P_DEVICE block device partition $P_PATH for resizefs"
		else
			log "kpartx map fail!${kpartxinfo}"
			return
		fi		
	else
		log "can not find kpartx"
		return
	fi
}

kpartx_unmap_partition(){
	log "kpartx_unmap_partition call DEVICE:$DEVICE P_DEVICE:$P_DEVICE"
	if [ -b $DEVICE ];then
		log "$DEVICE is a block device. do nothing!"
	else
		kpartxbin="`which kpartx 2>/dev/null`"
		if [ -n "$kpartxbin" ];then
			kpartx_dv_result="`$kpartxbin -dv $P_DEVICE`"
			log "kpartx_dv_result:$kpartx_dv_result"
			sleep 2
			losetup_a="`losetup -a | awk -F ' ' '{print $1}' | grep "${P_DEVICE}:"`"
			if [ -z "$losetup_a" ];then
				log "detach losetup device $P_DEVICE success."
				return 
			fi
			i=0
			while [ -n "$losetup_a" ];do
				$kpartxbin -dv $P_DEVICE
				sleep 2
				losetup -d $P_DEVICE
				
				losetup_a="`losetup -a | awk -F ' ' '{print $1}' | grep "${P_DEVICE}:"`"
				
				i=`expr $i + 1`
				if [ -n "$losetup_a" ];then
					if [ $i -eq 3 ];then
						log "detach losetup device fail!"
						return
					fi
					log "can not detach losetup device $P_DEVICE, retry $i..."
				else
					log "detach losetup device $P_DEVICE success."
					return 
				fi
				
			done
		else
			log "can not find kpartx, kpartx_unmap_partition do nothing!"
			return
		fi
	fi
}

resize_latest_partition(){
	if [ -z "$DEVICE" ];then
		log "DEVICE is null. do nothing"
		return
	fi
	is_gpt_error=`parted $DEVICE --script print| awk 'NR==1' | awk -F ' ' '{print $1}'`
	sgdiskbin="`which sgdisk 2>/dev/null`"
	if [ "$is_gpt_error"x = "Error:"x  ];then
		log "error:GPT table is not at the end of the disk. Fix it!!!"
		if [ -n "$sgdiskbin" ];then
			log "$sgdiskbin -e $DEVICE"
			$sgdiskbin -e $DEVICE
		else
			log "can not fix gpt table end partition for all of the space available"
			return
		fi
	else
		error_info_file="/tmp/parted-${DEVICE_NAME}-error-info${UUID}"
		parted $DEVICE --script print 2>$error_info_file
		is_err_info=`cat $error_info_file | awk 'NR==1' |awk -F "," '{print $1}'`
		if [ -n "$is_err_info" ];then
			if [ "$is_err_info"x = "Warning: Not all of the space available to ${DEVICE} appears to be used"x ] \
					|| [ "$is_err_info"x = "Error: The backup GPT table is corrupt"x ] \
					|| [ "$is_err_info"x = "Error: The backup GPT table is not at the end of the disk"x ];then
				log "Warning: Not all of the space available to ${DEVICE} appears to be used. Fix it!!!"
				if [ -n "$sgdiskbin" ];then
					log "$sgdiskbin -e $DEVICE"
					$sgdiskbin -e $DEVICE
				else
					log "can not fix gpt table end partition for all of the space available"
					return
					#parted $DEVICE print Fix
				fi
			else
				log "`cat $error_info_file`"
				return
			fi
		fi
		
	fi
	p_table_type=`parted $DEVICE print | grep "Partition Table" |awk -F ":" '{print $2}' |sed "s/^[ \s]\{1,\}//g"` 
	log "p_table_type:$p_table_type"
	p_num=`parted $DEVICE print | grep -v '^$' | tail -1 |awk -F " " '{print $1}'`
	log "p_num:$p_num"
	if [ "$p_num"x = "Number"x ];then
		log "error:can not get partition."
		return
	fi
	p_start=`parted $DEVICE 'unit s print' | grep -v '^$' | tail -1 |awk -F " " '{print $2}'`
	log "p_start:$p_start"
	if [ "$p_table_type"x = "gpt"x ] ;then
		log "gpt get p_tyte"
		p_type="primary"
		p_fstype=`parted $DEVICE print | grep -v '^$' | tail -1 |awk -F " " '{print $5}'`
		
	
	elif [ "$p_table_type"x = "msdos"x ] ;then
		log "msdos get p_tyte"
		p_type=`parted $DEVICE print | grep -v '^$' | tail -1 |awk -F " " '{print $5}'`
		p_fstype=`parted $DEVICE print | grep -v '^$' | tail -1 |awk -F " " '{print $6}'`
	fi
	log "p_type:$p_type"
	log "p_fstype:$p_fstype"
	p_fstype_uppercase=$(echo $p_fstype | tr '[a-z]' '[A-Z]') 
	if [ "$p_fstype_uppercase"x = "LVM"x ];then
		log "lvm partition not support."
		return
	fi
	p_flags=""
	p_nf=`parted $DEVICE print | grep -v '^$' | tail -1 |awk -F " " '{print $NF}'`
	
	if [ "$p_nf"x = "boot"x ] || [ "$p_nf"x = "msftdata"x ];then
		p_flags=$p_nf
	fi
	log "p_flags:$p_flags"
	# args = ["parted","--script",device,"mkpart","primary",fstype,start,end]
	if [ -n "$p_table_type" ] && [ -n "$p_num" ] && [ -n "$p_start" ] && [ -n "$p_type" ] && [ -n "$p_fstype" ];then
		parted --script $DEVICE rm $p_num
		mkpart_result_file="/tmp/${DEVICE_NAME}_mkpart_result_${UUID}"
		parted --script $DEVICE mkpart $p_type $p_fstype $p_start 100% 2>$mkpart_result_file
		mkpart_result="`cat $mkpart_result_file`"
		if [ -n "$mkpart_result" ];then
				log "parted $DEVICE mkpart fail. error:$mkpart_result"
				return
		else
				Parted_resize_result="success"
				log "parted $DEVICE mkpart success"
		fi
		
		if [ -n "$p_flags" ];then
			parted --script $DEVICE toggle $p_num $p_flags
		fi
	
		log "resize partition success."
	else
		log "can not get partition all arg. do nothing!!!"
	fi

}

log(){
	if [ "$LOG_LEVEL"x = "debug"x ];then
		if [ "$LOG_OUTPUT"x = "cmd"x ];then
			echo $@
		elif [ "$LOG_OUTPUT"x = "file"x ];then
			echo "`date '+%Y-%m-%d %H:%M:%S'` $@" >>$LOG_FILE
		fi
	fi
	
}




main(){
	genuuid
	if [ -b $DEVICE ];then
		log "$DEVICE is a block device"
		resize_latest_partition
	else
		log "$DEVICE maybe is a file. get file format (raw,qcow2)"
		qemuimgbin="`which qemu-img 2>/dev/null`"
		if [ -n "$qemuimgbin" ];then
			file_format="`$qemuimgbin info $DEVICE | grep "file format:" | awk -F ' ' '{print $3}'`"
			if [ -n "$file_format" ];then
				log "get $DEVICE file format: $file_format"
				if [ "$file_format"x = "qcow2"x ];then
					qemunbdbin="`which qemu-nbd 2>/dev/null`"
					if [ -n "$qemunbdbin" ];then
						load_nbd
						if [ "$load_nbd_result"x = "success"x ];then
							IS_USE_NBD="true"
							attach_nbd
							resize_latest_partition
						else
							log "load nbd fail. not support qcow2 file resize"
							return 
						fi
						
					else
						log "can not find qemu-nbd,not support qcow2 file resize"
						return
					fi
				elif [ "$file_format"x = "raw"x ];then	
					resize_latest_partition
				fi
			else
				log "cat not get $DEVICE file format"
				#return
			fi
		else 
			log "not qemu-img commond. do nothing!"
			return
		fi
	fi		
		
	if [ "$Parted_resize_result"x = "success"x ];then
		resize_fs
	fi
	if [ "$IS_USE_NBD"x = "true"x ];then
		detach_nbd
	fi
	echo "RESIZE_STATUS=$RESIZE_STATUS" > /tmp/${DEVICE_NAME}_extend_partition_result
}

main


