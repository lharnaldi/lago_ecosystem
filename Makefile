# 'make' builds everything
# 'make clean' deletes everything except source files and Makefile
#
# You need to set NAME, PART and PROC for your project.
# NAME is the base name for most of the generated files.

# solves problem with awk while building linux kernel
# solution taken from http://www.googoolia.com/wp/2015/04/21/awk-symbol-lookup-error-awk-undefined-symbol-mpfr_z_sub/
LD_LIBRARY_PATH =

NAME = led_blinker
PART = xc7z010clg400-1
PROC = ps7_cortexa9_0

TEMP = tmp

CORES = axi_axis_reader_v1_0 \
				axi_axis_writer_v1_0 \
				axi_bram_reader_v1_0 \
				axi_cfg_register_v1_0 \
				axis_adpll_v1_0 \
				axis_bram_reader_v1_0 \
				axis_bram_writer_v1_0 \
				axis_constant_v1_0 \
				axis_counter_v1_0 \
				axis_dc_removal_v1_0 \
				axis_decimator_v1_0 \
				axis_gpio_reader_i_v1_0 \
				axis_gpio_reader_v1_0 \
				axis_histogram_v1_0 \
				axis_interpolator_v1_0 \
				axis_lago_trigger_v1_0 \
				axis_lago_trigger_v1_1 \
				axis_lago_trigger_v1_2 \
				axis_lago_trigger_v1_3 \
				axis_lpf_v1_0 \
				axis_oscilloscope_v1_0 \
				axis_packetizer_v1_0 \
				axis_ram_writer_v1_0 \
				axis_rp_adc_v1_0 \
				axis_rp_dac_v1_0 \
				axis_tlast_gen_v1_0 \
				axis_trigger_v1_0 \
				axi_sts_register_v1_0 \
				axis_variable_v1_0 \
				axis_zero_crossing_det_v1_0 \
				axis_zeroer_v1_0 \
				bram_counter_v1_0 \
				dc_removal_v1_0 \
				dna_reader_v1_0 \
				int_counter_v1_0 \
				pps_gen_v1_0 \
				pps_gen_v1_1 \
				pwm_gen_v1_0 \
				ramp_gen_v1_0 


VIVADO = vivado -nolog -nojournal -mode batch
HSI = hsi -nolog -nojournal -mode batch
RM = rm -rf

UBOOT_TAG = xilinx-v2016.4
LINUX_TAG = xilinx-v2016.4
DTREE_TAG = xilinx-v2016.4

UBOOT_DIR = $(TEMP)/u-boot-xlnx-$(UBOOT_TAG)
LINUX_DIR = $(TEMP)/linux-xlnx-$(LINUX_TAG)
DTREE_DIR = $(TEMP)/device-tree-xlnx-$(DTREE_TAG)

UBOOT_TAR = $(TEMP)/u-boot-xlnx-$(UBOOT_TAG).tar.gz
LINUX_TAR = $(TEMP)/linux-xlnx-$(LINUX_TAG).tar.gz
DTREE_TAR = $(TEMP)/device-tree-xlnx-$(DTREE_TAG).tar.gz

UBOOT_URL = https://github.com/Xilinx/u-boot-xlnx/archive/$(UBOOT_TAG).tar.gz
LINUX_URL = https://github.com/Xilinx/linux-xlnx/archive/$(LINUX_TAG).tar.gz
DTREE_URL = https://github.com/Xilinx/device-tree-xlnx/archive/$(DTREE_TAG).tar.gz

LINUX_CFLAGS = "-O2 -march=armv7-a -mcpu=cortex-a9 -mtune=cortex-a9 -mfpu=neon -mfloat-abi=hard"
UBOOT_CFLAGS = "-O2 -march=armv7-a -mcpu=cortex-a9 -mtune=cortex-a9 -mfpu=neon -mfloat-abi=hard"
ARMHF_CFLAGS = "-O2 -march=armv7-a -mcpu=cortex-a9 -mtune=cortex-a9 -mfpu=neon -mfloat-abi=hard"

RTL8188_TAR = tmp/rtl8188EUS_linux_v5.2.2.4_25483.20171222.tar.gz
RTL8188_URL = https://www.dropbox.com/s/scjfthb9dck99cy/rtl8188EUS_linux_v5.2.2.4_25483.20171222.tar.gz?dl=0

.PRECIOUS: $(TEMP)/cores/% $(TEMP)/%.xpr $(TEMP)/%.hwdef $(TEMP)/%.bit $(TEMP)/%.fsbl/executable.elf $(TEMP)/%.tree/system.dts

all: boot.bin uImage devicetree.dtb fw_printenv

xpr: $(TEMP)/$(NAME).xpr

bit: $(TEMP)/$(NAME).bit

$(UBOOT_TAR):
	mkdir -p $(@D)
	curl -L $(UBOOT_URL) -o $@

$(LINUX_TAR):
	mkdir -p $(@D)
	curl -L $(LINUX_URL) -o $@

$(DTREE_TAR):
	mkdir -p $(@D)
	curl -L $(DTREE_URL) -o $@

$(RTL8188_TAR):
	mkdir -p $(@D)
	curl -L $(RTL8188_URL) -o $@

$(UBOOT_DIR): $(UBOOT_TAR)
	mkdir -p $@
	tar -zxf $< --strip-components=1 --directory=$@
	patch -d tmp -p 0 < patches/u-boot-xlnx-$(UBOOT_TAG).patch
	cp patches/zynq_red_pitaya_defconfig $@/configs
	cp patches/zynq-red-pitaya.dts $@/arch/arm/dts
	cp patches/zynq_red_pitaya.h $@/include/configs
	cp patches/u-boot-lantiq.c $@/drivers/net/phy/lantiq.c

$(LINUX_DIR): $(LINUX_TAR) $(RTL8188_TAR) 
	mkdir -p $@
	tar -zxf $< --strip-components=1 --directory=$@
	mkdir -p $@/drivers/net/wireless/realtek/rtl8188eu
	tar -zxf $(RTL8188_TAR) --strip-components=1 --directory=$@/drivers/net/wireless/realtek/rtl8188eu
	patch -d tmp -p 0 < patches/linux-xlnx-$(LINUX_TAG).patch
	patch -d tmp -p 0 < patches/driver_rtl8188_Makefile.patch
	patch -d tmp -p 0 < patches/driver_rtl8188_Kconfig.patch
	cp patches/linux-lantiq.c $@/drivers/net/phy/lantiq.c

$(DTREE_DIR): $(DTREE_TAR)
	mkdir -p $@
	tar -zxf $< --strip-components=1 --directory=$@

uImage: $(LINUX_DIR)
	make -C $< mrproper
	make -C $< ARCH=arm xilinx_zynq_defconfig
	make -C $< ARCH=arm CFLAGS=$(LINUX_CFLAGS) \
	  -j $(shell nproc 2> /dev/null || echo 1) \
	  CROSS_COMPILE=arm-linux-gnueabihf- UIMAGE_LOADADDR=0x8000 uImage modules
	cp $</arch/arm/boot/uImage $@

$(TEMP)/u-boot.elf: $(UBOOT_DIR)
	mkdir -p $(@D)
	make -C $< mrproper
	make -C $< ARCH=arm zynq_red_pitaya_defconfig
	make -C $< ARCH=arm CFLAGS=$(UBOOT_CFLAGS) \
	  CROSS_COMPILE=arm-linux-gnueabihf- all
	cp $</u-boot $@

fw_printenv: $(UBOOT_DIR) $(TEMP)/u-boot.elf
	make -C $< ARCH=arm CFLAGS=$(ARMHF_CFLAGS) \
	  CROSS_COMPILE=arm-linux-gnueabihf- env
	cp $</tools/env/fw_printenv $@

boot.bin: $(TEMP)/$(NAME).fsbl/executable.elf $(TEMP)/$(NAME).bit $(TEMP)/u-boot.elf
	echo "img:{[bootloader] $^}" > $(TEMP)/boot.bif
	bootgen -image $(TEMP)/boot.bif -w -o i $@

devicetree.dtb: uImage $(TEMP)/$(NAME).tree/system.dts
	$(LINUX_DIR)/scripts/dtc/dtc -I dts -O dtb -o devicetree.dtb \
	  -i $(TEMP)/$(NAME).tree $(TEMP)/$(NAME).tree/system.dts

$(TEMP)/cores/%: cores/%/core_config.tcl cores/%/*.vhd
	mkdir -p $(@D)
	$(VIVADO) -source scripts/core.tcl -tclargs $* $(PART)

$(TEMP)/%.xpr: projects/% $(addprefix $(TEMP)/cores/, $(CORES))
	mkdir -p $(@D)
	$(VIVADO) -source scripts/project.tcl -tclargs $* $(PART)

$(TEMP)/%.hwdef: $(TEMP)/%.xpr
	mkdir -p $(@D)
	$(VIVADO) -source scripts/hwdef.tcl -tclargs $*

$(TEMP)/%.bit: $(TEMP)/%.xpr
	mkdir -p $(@D)
	$(VIVADO) -source scripts/bitstream.tcl -tclargs $*

$(TEMP)/%.fsbl/executable.elf: $(TEMP)/%.hwdef
	mkdir -p $(@D)
	$(HSI) -source scripts/fsbl.tcl -tclargs $* $(PROC)

$(TEMP)/%.tree/system.dts: $(TEMP)/%.hwdef $(DTREE_DIR)
	mkdir -p $(@D)
	$(HSI) -source scripts/devicetree.tcl -tclargs $* $(PROC) $(DTREE_DIR)
	patch $@ patches/devicetree.patch

clean:
	$(RM) uImage fw_printenv boot.bin devicetree.dtb tmp
	$(RM) .Xil usage_statistics_webtalk.html usage_statistics_webtalk.xml
	$(RM) vivado*.jou vivado*.log
	$(RM) webtalk*.jou webtalk*.log
