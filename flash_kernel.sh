#!/system/bin/sh
#===============================================================
#  flash_kernel.sh
#  从 AnyKernel3 zip 提取内核，magiskboot repack 后刷入当前槽位
#  用法: sudo sh flash_kernel.sh
#===============================================================

ZIP="/storage/emulated/0/Download/AnyKernel3_none__6.1_android14-11-o-g42bfd68925d3.zip"
TMPDIR="/tmp/flash_kernel"
BOOT_IMG="$TMPDIR/boot.img"
NEW_BOOT="$TMPDIR/new-boot.img"

# ---- 1. 清理并创建临时目录 ----
rm -rf "$TMPDIR"
mkdir -p "$TMPDIR"

# ---- 2. 从 zip 提取 magiskboot 和 Image ----
echo "[*] 提取 magiskboot 和 Image ..."
unzip -o "$ZIP" tools/magiskboot Image -d "$TMPDIR" 2>/dev/null
chmod +x "$TMPDIR/tools/magiskboot"
MAGISKBOOT="$TMPDIR/tools/magiskboot"

# ---- 3. 检测当前槽位 ----
SLOT=$(getprop ro.boot.slot_suffix 2>/dev/null)
[ -z "$SLOT" ] && SLOT=$(getprop ro.boot.slot 2>/dev/null)
[ -z "$SLOT" ] && SLOT="_a"
echo "[*] 当前槽位: boot$SLOT"

# ---- 4. 寻找 boot 分区 ----
BOOT_PART=""
for p in /dev/block/by-name/boot$SLOT /dev/block/bootdevice/by-name/boot$SLOT; do
    [ -b "$p" ] && { BOOT_PART="$p"; break; }
done
if [ -z "$BOOT_PART" ]; then
    for p in /dev/block/platform/*/by-name/boot$SLOT /dev/block/platform/*/by-name/boot; do
        [ -b "$p" ] && { BOOT_PART="$p"; break; }
    done
fi
if [ -z "$BOOT_PART" ]; then
    echo "[!] 找不到 boot 分区"
    ls -la /dev/block/by-name/ 2>/dev/null | grep boot
    exit 1
fi
echo "[*] boot 分区: $BOOT_PART"

# ---- 5. dump 当前 boot ----
echo "[*] Dump 当前 boot ..."
dd if="$BOOT_PART" of="$BOOT_IMG" bs=1M 2>/dev/null || { echo "[!] dump 失败"; exit 1; }
sync

# ---- 6. magiskboot repack（Image -> kernel 替换） ----
cd "$TMPDIR"
echo "[*] magiskboot repack 中 ..."
# repack 会读取 boot.img 的 header，用当前目录的 kernel 文件替换
# 把 Image 作为 kernel 供 repack 使用
cp -f Image kernel
"$MAGISKBOOT" repack "$BOOT_IMG" "$NEW_BOOT" 2>&1

if [ ! -f "$NEW_BOOT" ]; then
    echo "[!] repack 失败"
    exit 1
fi

# ---- 7. 大小检查 ----
BOOT_SIZE=$(blockdev --getsize64 "$BOOT_PART" 2>/dev/null)
[ -z "$BOOT_SIZE" ] && BOOT_SIZE=$(stat -Lc%s "$BOOT_PART" 2>/dev/null)
NEW_SIZE=$(stat -c%s "$NEW_BOOT")
echo "[*] 分区容量: ${BOOT_SIZE:-未知} 字节"
echo "[*] 新镜像:   $NEW_SIZE 字节"
[ -n "$BOOT_SIZE" ] && [ "$NEW_SIZE" -gt "$BOOT_SIZE" ] && echo "[!] 新镜像超过分区容量"

# ---- 8. 确认写入 ----
echo ""
echo "========================================"
echo "  写入目标: $BOOT_PART"
echo "========================================"
echo -n "是否确认 dd 写回？(输入 YES): "
read ANSWER

if [ "$ANSWER" = "YES" ]; then
    echo "[*] 写入中 ..."
    dd if="$NEW_BOOT" of="$BOOT_PART" bs=1M 2>/dev/null
    sync
    echo "[✓] 写入完成，重启生效"
else
    echo "[-] 已取消"
    echo "    手动: dd if=$NEW_BOOT of=$BOOT_PART bs=1M"
fi
