#!/system/bin/sh
MODDIR=${0%/*}
RVPATH=/data/adb/rvhc/${MODDIR##*/}.apk
. "$MODDIR/config"

err() {
	[ ! -f "$MODDIR/err" ] && cp "$MODDIR/module.prop" "$MODDIR/err"
	sed -i "s/^des.*/description=⚠️ Needs reflash: '${1}'/g" "$MODDIR/module.prop"
}

until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 1; done
until [ -d "/sdcard/Android" ]; do sleep 1; done

rm -f ${MODDIR}/packages.xml
if [ ! -f "/data/system/packages.xml" ]; then
	err "packages.xml not found"
	exit
elif [ -z "$(file /data/system/packages.xml | grep 'Binary')" ]; then
	cp -f /data/system/packages.xml ${MODDIR}/packages.xml
elif ! which abx2xml >/dev/null; then
	err "abx2xml tool not found"
	exit
else
	abx2xml /data/system/packages.xml ${MODDIR}/packages.xml
fi

PACKAGE_INFO=$(grep "<package name=\"${PKG_NAME}\"" ${MODDIR}/packages.xml)
rm -f ${MODDIR}/packages.xml

if [ -z "${PACKAGE_INFO}" ]; then
	err "app not installed"
	exit
fi

BASEPATH=$(echo ${PACKAGE_INFO} | awk -F 'codePath="' '{print $2}' | awk -F '"' '{print $1}')

if [ ! -d "$BASEPATH/lib" ]; then
	err "zygote crashed (fix your ROM)"
	exit
fi

VERSION=$(dumpsys package "$PKG_NAME" | grep -m1 versionName) VERSION="${VERSION#*=}"
if [ "$VERSION" != "$PKG_VER" ] && [ "$VERSION" ]; then
	err "version mismatch (installed:${VERSION}, module:$PKG_VER)"
	exit
fi

grep "$PKG_NAME" /proc/mounts | while read -r line; do
	mp=${line#* } mp=${mp%% *}
	umount -l "${mp%%\\*}"
done

if ! chcon u:object_r:apk_data_file:s0 "$RVPATH"; then
	err "apk not found"
	exit
fi

mount -o bind "$RVPATH" "$BASEPATH/base.apk"
am force-stop "$PKG_NAME"

[ -f "$MODDIR/err" ] && mv -f "$MODDIR/err" "$MODDIR/module.prop"
