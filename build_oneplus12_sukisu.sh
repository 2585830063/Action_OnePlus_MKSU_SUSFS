#!/bin/bash

# 固定使用默认参数
CPU="sm8650"
FEIL="oneplus12_v"
CPUD="pineapple"
ANDROID_VERSION="android14"
KERNEL_VERSION="6.1"
KERNEL_NAME="-android14-11-o-qiuqiu"
kernelsu_variant="SukiSU"
kernelsu_version="main"
SUSFS_ENABLED="true"
VFS_patch_ENABLED="enable"

# 配置Git
git config --global user.name "2585830063"
git config --global user.email "2585830063@qq.com"

# 安装依赖
sudo apt update && sudo apt upgrade -y
sudo apt install -y python3 git curl bc build-essential flex bison libssl-dev libelf-dev

# 安装repo
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/repo
chmod a+x ~/repo
sudo mv ~/repo /usr/local/bin/repo

# 初始化仓库
mkdir -p kernel_workspace
cd kernel_workspace || exit
repo init -u https://github.com/OnePlusOSS/kernel_manifest.git \
    -b refs/heads/oneplus/"$CPU" \
    -m "$FEIL".xml \
    --depth=1
repo sync -j$(nproc)

# 清理版本信息
rm -f kernel_platform/common/android/abi_gki_protected_exports_*
rm -f kernel_platform/msm-kernel/android/abi_gki_protected_exports_*
sed -i 's/ -dirty//g' kernel_platform/common/scripts/setlocalversion
sed -i 's/ -dirty//g' kernel_platform/msm-kernel/scripts/setlocalversion

# 处理KernelSU
if [[ "$kernelsu_variant" == "SukiSU" ]]; then
    cd kernel_platform || exit
    curl -LSs "https://raw.githubusercontent.com/ShirkNeko/KernelSU/main/kernel/setup.sh" | bash -s -- "-s susfs-dev"
    KSU_VERSION=$(expr $(git -C KernelSU rev-list --count HEAD) "+" 10506)
    
    # 应用SUSFS补丁
    if [[ "$SUSFS_ENABLED" == "true" ]]; then
        git clone https://gitlab.com/simonpunk/susfs4ksu.git -b gki-"$ANDROID_VERSION"-"$KERNEL_VERSION"
        git clone https://github.com/ShirkNeko/SukiSU_patch.git
        
        cp susfs4ksu/kernel_patches/50_add_susfs_in_gki-"$ANDROID_VERSION"-"$KERNEL_VERSION".patch common/
        cp -r susfs4ksu/kernel_patches/fs/* common/fs/
        cp -r susfs4ksu/kernel_patches/include/linux/* common/include/linux/
        
        pushd common || exit
        patch -p1 < 50_add_susfs_in_gki-"$ANDROID_VERSION"-"$KERNEL_VERSION".patch || true
        cp ../SukiSU_patch/69_hide_stuff.patch .
        patch -p1 -F 3 < 69_hide_stuff.patch
        popd || exit
    fi

    # 应用VFS补丁
    if [[ "$VFS_patch_ENABLED" == "enable" ]]; then
        pushd common || exit
        cp ../../SukiSU_patch/hooks/new_hooks.patch .
        patch -p1 -F 3 < new_hooks.patch
        popd || exit
    fi

    # 修改内核配置
    cat << EOF >> common/arch/arm64/configs/gki_defconfig
CONFIG_KSU=y
CONFIG_KSU_MANUAL_HOOK=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
EOF

    sed -i 's/check_defconfig//' common/build.config.gki
fi

# 修改内核名称
sed -i '$s|echo "$res"|echo "'"$KERNEL_NAME"'"|' kernel_platform/common/scripts/setlocalversion
sed -i "/stable_scmversion_cmd/s/-maybe-dirty//g" kernel_platform/build/kernel/kleaf/impl/stamp.bzl

# 编译内核
if [[ "$CPU" == "sm8650" ]]; then
    ./kernel_platform/build_with_bazel.py -t "$CPUD" gki
else
    LTO=thin ./kernel_platform/oplus/build/oplus_build_kernel.sh "$CPUD" gki
fi

# 打包输出
mkdir -p AnyKernel3
cp kernel_platform/out/msm-kernel-"$CPUD"-gki/dist/Image AnyKernel3/
cp kernel_platform/out/msm-kernel-"$CPUD"-gki/dist/Image kernel_workspace/kernel

OUTPUT_DIR="Kernel_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"
mv AnyKernel3/* "$OUTPUT_DIR"/
mv kernel_workspace/kernel "$OUTPUT_DIR"/

echo "编译完成！输出文件保存在: $(pwd)/$OUTPUT_DIR"