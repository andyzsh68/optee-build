################################################################################
# QEMU (virt) + Trusted Services PSA Secure Partitions
#
# 在 qemu_v8.mk 的 FF-A/SPMC 基础设施之上，叠加 Trusted Services 的 PSA 服务
# SP 与对应的 Linux 用户态测试程序。对标 fvp-psa-sp.mk 之于 fvp.mk。
#
# 用法：
#     cd build && make -f qemu_v8-psa-sp.mk       # 构建
#     cd build && make -f qemu_v8-psa-sp.mk run   # 启动
#
# 形态：SPMC_AT_EL=1 —— SPMD 在 EL3(TF-A)，SPMC 在 S-EL1(OP-TEE)，
#       TS SP 在 S-EL0。SP 以 embedded 方式编入 OP-TEE 二进制。
#
# 为什么不直接用 qemu_v8.mk 的 SEL0_SPS=y：
#   qemu_v8.mk:453-467 的 SEL0_SPS 块是一体的 —— 它硬编码 SPMC_TESTS=y、
#   CFG_SPMC_TESTS=y，并无条件构建 4 个 spm-test SP，没有 PSA SP 的分支。
#   本文件故意保持 SEL0_SPS=n，自行复现该块所需的副作用（见下方 A 节），
#   再接入 PSA SP。好处是完全不必修改上游的 qemu_v8.mk。
################################################################################

################################################################################
# A. 复现 qemu_v8.mk 中 SEL0_SPS=y 的副作用（qemu_v8.mk:61-70）
#    这些必须在 include qemu_v8.mk 之前设置。
################################################################################
# SPMC 位于 S-EL1（OP-TEE）。qemu_v8.mk 用 ?= 定义，此处先赋值即可生效。
SPMC_AT_EL ?= 1
ifneq ($(SPMC_AT_EL),1)
$(error qemu_v8-psa-sp.mk 只支持 SPMC_AT_EL=1，当前为 $(SPMC_AT_EL))
endif

# 通过 9p 把主机目录挂进客户机，便于拷贝测试程序
QEMU_VIRTFS_AUTOMOUNT ?= y

# TS SP 打包方式：编入 OP-TEE 二进制（而非走 FIP）
SP_PACKAGING_METHOD ?= embedded

# 不构建 SPMC 测试 SP —— 本配置构建的是 PSA 服务 SP
SPMC_TESTS ?= n
ifneq ($(SPMC_TESTS),n)
$(error qemu_v8-psa-sp.mk 不构建 SPMC 测试 SP，请直接用 qemu_v8.mk SEL0_SPS=y)
endif

# TS SP 的构建配置（deployment 下的 config 目录名）
DEFAULT_SP_CONFIG	?= default-opteesp
SP_BLOCK_STORAGE_CONFIG	?= $(DEFAULT_SP_CONFIG)
SP_PSA_ITS_CONFIG	?= $(DEFAULT_SP_CONFIG)
SP_PSA_PS_CONFIG	?= $(DEFAULT_SP_CONFIG)
SP_LOGGING_CONFIG	?= $(DEFAULT_SP_CONFIG)

# 关闭 fTPM：qemu_v8.mk:52 默认 MEASURED_BOOT_FTPM ?= y，会构建 optee_ftpm，
# 而后者依赖 ms-tpm-20-ref 仓库。本工作区的主 manifest（fvp-ts.xml:17）明确
# 用 <remove-project> 移除了该仓库（注释："The fTPM is not used in this config"），
# 故此处必须关掉，否则报 "CFG_MS_TPM_20_REF not supplied or invalid"。
MEASURED_BOOT_FTPM	?= n

# 关闭 Rust TA 示例：qemu_v8.mk:47-49 在 x86_64 主机上默认 RUST_ENABLE ?= y，
# 会通过 buildroot 拉起 optee_rust_examples_ext，需要 optee_rust 仓库。
# 该仓库仅由 qemu_v8.xml 包含，本工作区（fvp-ts.xml）没有，故必须关掉，
# 否则 buildroot 报 "optee_rust does not exist"。
# 本任务的验证不需要 Rust TA 示例。
RUST_ENABLE		?= n

# 不构建 xtest：本配置不跑 SPMC 测试，xtest 对 TS 验证无用。
# 且本工作区的 optee_test 与 optee_os 版本不完全匹配（xtest 引用了
# TEE_ALG_PBKDF2_HMAC_SHA224_DERIVE_KEY 等本版 optee_os 尚未定义的宏），
# 强行构建会失败。fvp-psa-sp.mk:52-57 采用同样做法。
BR2_PACKAGE_OPTEE_TEST_EXT	?= n
BR2_PACKAGE_LIBOPENSSL		?= n
BR2_PACKAGE_OPENSSL		?= n

################################################################################
# B. 复用 qemu_v8.mk 的全部平台/SPMC 基础设施
################################################################################
include qemu_v8.mk

################################################################################
# C. OP-TEE：以 S-EL1 SPMC 身份管理 SP
#    qemu_v8.mk 已按 SPMC_AT_EL=1 给出 CFG_CORE_SEL1_SPMC=y，
#    这里补上 SP 管理与设备树相关开关（对标 fvp-psa-sp.mk:90-95）。
################################################################################
OPTEE_OS_COMMON_EXTRA_FLAGS += CFG_SECURE_PARTITION=y
OPTEE_OS_COMMON_EXTRA_FLAGS += CFG_CORE_HEAP_SIZE=131072
OPTEE_OS_COMMON_EXTRA_FLAGS += CFG_DT=y
OPTEE_OS_COMMON_EXTRA_FLAGS += CFG_MAP_EXT_DT_SECURE=y
# 单个 SP 启动失败时继续启动其余 SP，便于定位问题
OPTEE_OS_COMMON_EXTRA_FLAGS += CFG_SP_SKIP_FAILED=y

################################################################################
# D. Linux：追加 TS 所需的 kconfig 片段
#    qemu_v8.mk:423-425 用 := 赋值，故此处用 += 追加。
################################################################################
LINUX_DEFCONFIG_COMMON_FILES += $(CURDIR)/kconfigs/qemu_trusted-services.conf
# arm-ffa-user.ko 等需要内核模块支持
LINUX_COMMON_TARGETS += modules

################################################################################
# E. Trusted Services：SP 与用户态测试程序
################################################################################
include trusted-services.mk

# ---- Secure Partitions（S-EL0）--------------------------------------------
#
# 只构建不依赖 FVP 平台硬件的 SP。已排除：
#   crypto      —— default_crypto.dts.in 硬编码 FVP 的 TRNG 地址 0x7fe60000
#                  （juno_trng 驱动），QEMU virt 无此设备
#   attestation —— 依赖 crypto
#   smm-gateway —— 需要 UEFI MM carveout 与配套 DTB 改动
#   logging     —— 【实测确认】其 manifest 声明 device-regions.uart
#                  base-address = <0x0 0x1c0b0000>（FVP 的 PL011）。
#                  QEMU virt 的 UART 在 0x09000000，该 SP 会访问不存在的 MMIO
#                  并挂起，导致 SPMC 既不启动后续 SP 也不交还 NWd。
#                  若要启用，需先为 QEMU 定制其 manifest 的 uart 地址。
#
# 已实测：block-storage / ITS / PS 三者的生成 manifest 均**不含**
# device-regions 与 memory-regions，故不依赖任何平台特定 MMIO。
#
# TS_PLATFORM 沿用各 deployment 的默认值 arm/fvp/fvp_base_revc-2xaemv8a：
# 对这 3 个 SP 而言该 provider 只提供 SFS 存储参数（CFG_SFS_*），
# 不含硬件驱动映射，故对 QEMU 无害。（不能改用 ts/vanilla —— 它在存在
# 任何驱动依赖时会 FATAL_ERROR。）
#
# 启动次序由 manifest 的 boot-order 决定（OP-TEE 的 insert_session_ordered()
# 按该字段有序插入）；下方调用顺序与之保持一致，避免两套机制冲突。
TS_LOGGING_SP ?= n
ifeq ($(TS_LOGGING_SP),y)
$(eval $(call build-sp,logging,config/$(SP_LOGGING_CONFIG),da9dffbd-d590-40ed-975f-19c65a3d52d3,$(SP_LOGGING_EXTRA_FLAGS)))
endif
$(eval $(call build-sp,block-storage,config/$(SP_BLOCK_STORAGE_CONFIG),63646e80-eb52-462f-ac4f-8cdf3987519c,$(SP_BLOCK_STORAGE_EXTRA_FLAGS)))
$(eval $(call build-sp,internal-trusted-storage,config/$(SP_PSA_ITS_CONFIG),dc1eef48-b17a-4ccf-ac8b-dfcff7711b14,$(SP_PSA_ITS_EXTRA_FLAGS)))
$(eval $(call build-sp,protected-storage,config/$(SP_PSA_PS_CONFIG),751bf801-3dde-4768-a514-0f10aeed1790,$(SP_PSA_PS_EXTRA_FLAGS)))

# ---- Linux 用户态测试程序 ---------------------------------------------------
#
# 不含 psa-api-test/crypto 与 initial_attestation —— 对应的 SP 未构建。
$(eval $(call build-ts-app,libts,$(TS_APP_LIBTS_EXTRA_FLAGS)))
$(eval $(call build-ts-app,libpsats,$(TS_APP_LIBPSATS_EXTRA_FLAGS)))
$(eval $(call build-ts-app,ts-service-test,$(TS_APP_TS_SERVICE_TEST_EXTRA_FLAGS)))
$(eval $(call build-ts-app,psa-api-test/internal_trusted_storage,$(TS_APP_PSA_ITS_EXTRA_FLAGS)))
$(eval $(call build-ts-app,psa-api-test/protected_storage,$(TS_APP_PSA_PS_EXTRA_FLAGS)))

clean: ffa-test-all-clean ffa-sp-all-clean
