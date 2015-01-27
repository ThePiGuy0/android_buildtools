#!/bin/bash
#################################################
#
# This is a build script helper for sediROM
#
#################################################

# defines the maximum cpu's you want to use. Valid for AOSP builds only because
# for CM we always use mka / all CPUs
MAXCPU=8

SRCDIR="build/envsetup.sh"
[ ! -f $SRCDIR ]&& echo "Are you in the root dir??? aborted." && exit 3

# help/usage
F_HELP(){
	echo USAGE:
	echo
	echo "$0 needs one of:" 
	echo "	systemimage|userdataimage|otapackage|bootimage|recovery|mr_twrp|multirom|trampoline|multirom_zip|free|showtargets"
	echo 
	echo "	e.g.: $0 otapackage"
	echo 
	echo "You can also add a 'make clean or make installclean' by given it as the second arg"
	echo "	valid options are: clean|installclean"
	echo
	echo "	e.g.: $0 otapackage clean"
	echo
	echo "Special commands:"
	echo "	<free>		You will be asked what target you want. No limits ;-)" 
	echo "	<showtargets>	Scans for all available targets and creates a file output."
	echo 
	echo "Special variables:"
	echo "	BUILDID		if you call 'BUILDID=samsung/i927 $0' you will skip that question"
	echo "	LOKIFY		if you set this to 1 we will lokify at the end"
	echo
}
# check if we have at least 1 arg:
[ -z $1 ]&& echo -e "MISSING ARG. \n\n" && F_HELP && exit 3

case $1 in
	-h|--help)
		F_HELP
		exit 0
        ;;
        showtargets)
            echo "Generating all available targets..."
            make -qp | awk -F':' '/^[a-zA-Z0-9][^$#\/\t=]*:([^=]|$)/ {split($1,A,/ /);for(i in A)print A[i]}' > alltargets
            echo "All available build targets can be found in the file './alltargets' now."
            exit
	;;
esac

source $SRCDIR
if [ -z $BUILDID ];then
    echo 
    echo "******************************************************************************************************"
    echo "Tell me the build id. It must match the one in device tree and need to include the vendor as well."
    echo
    echo "Example:"
    echo "lge/fx3q --> will look into device/lge/fx3q/"
    echo "or"
    echo "samsung/i927 --> will look into device/samsung/i927"
    echo "******************************************************************************************************"
    echo
    echo "Ok now give me your build id:"
    read BUILDID
else
    echo "BUILDID was predefined as $BUILDID"
fi
BUILDWHAT=$(egrep "^add_lunch_combo" device/$BUILDID/vendorsetup.sh |cut -d" " -f2)

# choose the right java JDK
echo ... enabling correct java version depending on which Android version you want to build..
BUILDJAV=$(echo ${PWD##*/})
case "$BUILDJAV" in
        aosp_ics)
        NEEDEDJAVA=java-6-oracle
	BUILDEXEC="make -j${MAXCPU}"
	;;
        aosp_jb)
        NEEDEDJAVA=java-1.6.0-openjdk-amd64
	BUILDEXEC="make -j${MAXCPU}"
        ;;
        aosp_kk)
        NEEDEDJAVA=java-7-oracle
	BUILDEXEC="make -j${MAXCPU}"
        ;;
        cm_ics)
	NEEDEDJAVA=java-6-oracle
	BUILDEXEC="mka"
        ;;
        cm_kk)
        NEEDEDJAVA=java-7-oracle
	BUILDEXEC="mka"
        ;;
        *)
        echo "cannot determine correct Java version! ABORTED"
        exit 3
        ;;
esac
sudo update-java-alternatives -s $NEEDEDJAVA
echo ... done

if [ $LOKIFY ];then

	# Loki specific
	LOKI="/home/xdajog/loki_tool"	# the loki patch binary
	ABOOT="/home/xdajog/aboot.img"	# the dd'ed image of aboot
	LOKINEED=boot.img		# the file which should be patched. will auto adjusted when you choosen 'recovery'
	LOKITYPE=boot			# the loki patch type. will auto adjusted when you choosen 'recovery' but not when 'mr_twrp'

	# Loki check
	if [ ! -f "$LOKI" ]||[ ! -f "$ABOOT" ];then
		echo missing loki binary. That means we can NOT lokifying for you!
		read DUMMY
		LOKIOK=3
	else
		echo "Great you have loki in place! So we are able to do loki for you at the end!"
		LOKIOK=0
	fi
else
	echo "Will not doing lokify because LOKIFY is not set."
fi

# check the targets
case $1 in
	otapackage|bootimage|systemimage|userdataimage)
		echo $1 choosen
		BUILDEXEC="$BUILDEXEC $1"
	;;
	multirom|trampoline|multirom_zip)
		echo $1 choosen
                BUILDEXEC="$BUILDEXEC $1"
		LOKIOK=1
		echo LOKI disabled because of your above choice
	;;
	recovery)
		echo $1 choosen
		BUILDEXEC="$BUILDEXEC ${1}image"
		LOKINEED=recovery.img
		LOKITYPE=recovery
	;;
	mr_twrp)
		echo $1 choosen
                BUILDEXEC="$BUILDEXEC recoveryimage"
                LOKINEED=recovery.img
		echo
		echo "***********************************************************"
		echo "PLEASE ENTER THE LOKI TYPE (can be 'boot' or 'recovery'):"
		read LOKITYPE
		echo "***********************************************************"
	;;
	mr_full)
		echo $1 choosen
		BUILDEXEC="$BUILDEXEC recoveryimage multirom trampoline"
		LOKINEED=recovery.img
		echo
		echo "***********************************************************"
                echo "PLEASE ENTER THE LOKI TYPE (can be 'boot' or 'recovery'):"
                read LOKITYPE
		echo "***********************************************************"
	;;
	free)
		echo "***********************************************************"
		echo "Enter your build choice (will NOT be verified!)"
		echo "Can be multiple one separated by space:"
		read BARG
		BUILDEXEC="$BUILDEXEC $BARG"
		echo "Do you want to LOKI? If so enter the Loki Type (recovery|boot) otherwise ENTER:"
		read "LOKITYPE"
		[ -z "$LOKITYPE" ]&& LOKIOK=1
		echo "***********************************************************"
	;;
	*)
		F_HELP
		exit 2
	;;
esac

if [ ! -z "$2" ];then
	case $2 in
		clean)
			echo will $2 before
			make $2
		;;
		installclean)
			echo will $2 before
			make $2
		;;
		*)
			echo unknown clean arg aborted
			exit 3
		;;
	esac
fi

source $SRCDIR && lunch $BUILDWHAT && time $BUILDEXEC

BUILDEND=$?

echo "... BUILD ended with errorlevel = $BUILDEND"

if [ $LOKIFY ] && [ $LOKIOK -eq 0 ]&&[ $BUILDEND -eq 0 ];then
	echo "Lokifying ($LOKINEED as $LOKITYPE)..."
	$LOKI patch $LOKITYPE $ABOOT out/target/product/fx3q/$LOKINEED out/target/product/fx3q/${LOKINEED}.lokied
else
	echo "... skipping loki"
fi


