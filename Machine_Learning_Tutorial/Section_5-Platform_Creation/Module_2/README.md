# Vitis AI Custom Platform Creation

In this module, we will create a custom platform to run Vitis-AI applications for ZCU104. Since ZCU104 is a validated board and Vivado has processing system presets, we will skip step 0 mentioned in previous module and start to build the full hardware and generate XSA. To prepare the software components, we will import XSA into PetaLinux project and do some configurations. After building software and hardware components, we'll package the platform. At last, we'll run Vitis-AI application on this platform to test this customized platform.

## Table of Contents

- [Custom Platform Planning](#custom-platform-planning)
- [Step 1: Create the Vivado Hardware Design and Generate XSA](#step-1-create-the-vivado-hardware-design-and-generate-xsa)
  - [Configuring Platform Interface Properties](#configuring-platform-interface-properties)
- [Step 2: Create the Software Components with PetaLinux](#step-2-create-the-software-components-with-petalinux)
- [Step 3: Create the Vitis Platform](#step-3-create-the-vitis-platform)
- [Step 4: Test the Platform](#step-4-test-the-platform)
  - [Prepare for the DPU Kernel](#prepare-for-the-dpu-kernel)
  - [Create and Build a Vitis application](#create-and-build-a-vitis-application)
  - [Prepare the Network Deployment File](#prepare-the-network-deployment-filebr-)
- [Reference](#reference)
- [More Information about Install and Set Vitis and XRT Environment](#more-information-about-install-and-set-vitis-and-xrt-environment)



## Custom Platform Planning

For the hardware part of Vitis AI design, DPU is integrated as RTL kernel. It's connected to the interfaces of platform and controlled by software running on ARM processor. DPU requires two clocks: clk and clk2x. We'll give 200MHz and 400MHz clocks for easy timing closure. DPU is a memory hungry IP so the platform needs to provide multiple AXI HP interfaces. 

On the software side, the platform needs to provide the XRT, ZOCL packages for Vitis-AI to control DPU. ZOCL is the kernel module that talks to acceleration kernels. It needs a device tree node so it will be added. Other Vitis-AI dependencies will also be added. The above are standard Vitis platform software settings. Common image provided by Xilinx can accomplish all these features. Besides these common features, we wish to add gcc compilers to do application native compilation, add mesa-megadriver for Vitis-AI demo applications and replace the dropbear with openssh so that the network speed can be faster.

## Step 1: Create the Vivado Hardware Design and Generate XSA

### Create Base Vivado Project from Preset

1. Source <Vitis_Install_Directory>/settings64.sh, and call Vivado out by typing "vivado" in the console.<br />

2. Create a Vivado project named zcu104_custom_platform.
      a) Select ***File->Project->New***.<br />
      b) Click ***Next***.<br />
      c) In Project Name dialog set Project name to ```zcu104_custom_platform```.<br />
      d) Click ***Next***.<br />
      e) Leaving all the setting to default until you goto the Default Part dialog.<br />
      f) Select ***Boards*** tab and then select ***Zynq UltraScale+ ZCU104 Evaluation Board***<br />
      g) Click ***Next***, and your project summary should like below:<br />
      ![vivado_project_summary.png](images/vivado_project_summary.png)<br />
      h) Then click ***Finish***<br />
   
3. Create a block design named system. <br />
   a) Select Create Block Design.<br />
   b) Change the design name to ```system```.<br />
   c) Click ***OK***.<br />

4. Add MPSoC IP and run block automation to configure it.<br />
   a) Right click Diagram view and select ***Add IP***.<br />
   b) Search for ```zynq``` and then double-click the ***Zynq UltraScale+ MPSoC*** from the IP search results.<br />
   c) Click the ***Run Block Automation*** link to apply the board presets.<br />
      In the Run Block Automation dialog, ensure the following is check marked:<br />
      - All Automation<br />
      - Zynq_ultra_ps_e_0<br />
      - Apply Board Presets<br />

   d) Click ***OK***. You should get MPSoC block configured like below:<br />
   ![block_automation_result.png](images/block_automation_result.png)<br />

***Note: At this stage, the Vivado block automation has added a Zynq UltraScale+ MPSoC block and applied all board presets for the ZCU104. For a custom board, please double click MPSoC block and setup parameters according to the board hardware. Next we'll add the IP blocks and metadata to create a base hardware design that supports acceleration kernels.***

### Customize System Design for Clock and Reset 

1. Re-Customizing the Processor IP Block<br />
   a) Double-click the Zynq UltraScale+ MPSoC block in the IP integrator diagram.<br />
   b) Select ***Page Navigator > PS-PL Configuration***.<br />
   c) Expand ***PS-PL Configuration > PS-PL Interfaces*** by clicking the ***>*** symbol.<br />
   d) Expand ***Master Interface***.<br />
   e) Uncheck the ***AXI HPM0 FPD*** and ***AXI HPM1 FPD*** interfaces.<br />
   f) Click OK.<br />
   g) Confirm that the IP block interfaces were removed from the Zynq UltraScale+ MPSoC symbol in your block design.<br />
   ![hp_removed.png](images/hp_removed.png)<br />

***Note: This is a little different from traditional Vivado design flow. In order to make AXI interfaces available in Vitis platform, you should disable these interfaces at Vivado IPI platform and enable them at platform interface properties. We will show you how to do that later***

2. Add clock block:<br />
   a) Right click Diagram view and select ***Add IP***.<br />
   b) Search for and add a ***Clocking Wizard*** from the IP Search dialog.<br />
   c) Double-click the ***clk_wiz_0*** IP block to open the Re-Customize IP dialog box.<br />
   d) Click the ***Output Clocks*** tab.<br />
   e) Enable clk_out1 through clk_out3 in the Output Clock column, rename them as ```clk_100m```, ```clk_200m```, ```clk_400m``` and set the Requested Output Freq as follows:<br />
   
      - ***clk_100m*** to ***100*** MHz.<br />
      - ***clk_200m*** to ***200*** MHz.<br />
   - ***clk_400m*** to ***400*** MHz.<br />
   
   f) At the bottom of the dialog box set the ***Reset Type*** to ***Active Low***.<br />
   g) Click ***OK*** to close the dialog.<br />
    The settings should like below:<br />
 ![clock_settings.png](images/clock_settings.png)<br />
***Note: So now we have set up the clock system for our design. This clock wizard uses the pl_clk as input clock and generates clocks needed for the whole logic design. In this simple design, we would use 100MHz clock as the axi_lite control bus clock. 200MHz and 400MHz clocks are reserved for DPU AXI interface clock and DPU core clock during design linking phase. You are free to modify the clock quantities and frequency to fit your target design. We'll setup the clock export in future steps. Before that, we need to create reset signals for each clock because they are needed in clock export setup.***
   
3. Add the Processor System Reset blocks:<br />
   a) Right click Diagram view and select ***Add IP***.<br />
   b) Search for and add a ***Processor System Reset*** from the IP Search dialog<br />
   c) Add 2 more ***Processor System Reset*** blocks, using the previous steps; or select the ***proc_sys_reset_0*** block and Copy (Ctrl-C) and Paste (Ctrl-V) it twice in the block diagram<br />
   d) Rename them as ```proc_sys_reset_100m```, ```proc_sys_reset_200m```, ```proc_sys_reset_400m``` by selecting the block and update ***Name*** in ***Block Properties*** window.
  
4. Connect Clocks and Resets: <br />
   a) Click ***Run Connection Automation***, which will open a dialog that will help connect the proc_sys_reset blocks to the clocking wizard clock outputs.<br />
   b) Enable All Automation on the left side of the Run Connection Automation dialog box.<br />
   c) Select ***clk_in1*** on clk_wiz_0, and set the Clock Source to ***/zynq_ultra_ps_e_0/pl_clk0***.<br />
   d) For each ***proc_sys_reset*** instance, select the ***slowest_sync_clk***, and set the Clock Source as follows:<br />
   
      - ***proc_sys_reset_100m*** with ***/clk_wiz_0/clk_100m***<br />
      - ***proc_sys_reset_200m*** with ***/clk_wiz_0/clk_200m***<br />
   - ***proc_sys_reset_400m*** with ***/clk_wiz_0/clk_400m***<br />
   
   e) On each proc_sys_reset instance, select the ***ext_reset_in***, set ***Board Part Interface*** to ***Custom*** and set the ***Select Manual Source*** to ***/zynq_ultra_ps_e_0/pl_resetn0***.<br />
   f) Make sure all checkboxes are enabled, and click ***OK*** to close the dialog and create the connections.<br />
   g) Connect all the ***dcm_locked*** signals on each proc_sys_reset instance to the locked signal on ***clk_wiz_0***.<br />
   Then the connection should like below:<br />
![clk_rst_connection.png](images/clk_rst_connection.png)

5. Click ***Window->Platform interfaces***, and then click ***Enable platform interfaces*** link to open the ***Platform Interfaces*** Window.
   
6. Enable ***clk_200m***, ***clk_400m***, ***clk_100m*** of clk_wiz_0, 

   - set ***id*** of ***clk_200m*** to ```0```, enable ***is default***
     set ***id*** of ***clk_400m*** to ```1```, 
     set ***id*** of ***clk_100m*** to ```2```, <br />![](images/platform_clock.png)
   
   ***Now we have added clock and reset IPs and enabled them for kernels to use***



### Add Interrupt Support

V++ linker can automatically link the interrupt signals between kernel and platform, as long as interrupt signals are exported by ***PFM.IRQ*** property in the platform. For simple designs, interrupt signals can be sourced by processor's ***pl_ps_irq***. We'll use AXI Interrupt Controller here because it can provide phase aligned clocks for DPU. We'll enable ***AXI HPM0 LPD*** to control AXI Interrupt Controller, add AXI Interrupt Controller and enable interrupt signals for ***PFM.IRQ***. Here are the detailed steps.

1. In the block diagram, double-click the ***Zynq UltraScale+ MPSoC*** block.

2. Select ***PS-PL Configuration > PS-PL interfaces > Master interface***.

3. Select the ***AXI HPM0 LPD*** check box, keep the ***AXI HPM0 LPD Data width*** settings as default ***32***.

   ***We use AXI HPM0 LPD mainly for controlling purpose. It only needs to read write 32 bit control registers.***

4. Click ***OK*** to finish the configuration.

5. Connect ***maxihpm0_lpd_aclk*** to ***/clk_wiz_0/clk_100m***.

6. Right click Diagram view and select ***Add IP***, search and add ***AXI Interrupt Controller*** IP.

7. Double click the AXI Interrupt Controller block, set ***Interrupts type*** to ```Level Interrupt```, set ***Level type*** to ```Active High```, set ***Interrupt Output Connection*** to ```Bus```. Click ***OK*** to save the change.
    ![intc_settings.png](images/intc_settings.png)

8. Click the AXI Interrupt Controller block and go to ***Block Properties -> Properties***, configure or make sure the parameters are set as following:
    ***C_ASYNC_INTR***: ```0xFFFFFFFF```.
    ![async_intr.png](images/async_intr.png)
    ***When interrupts generated from kernels are clocked by different clock domains, this option is useful to capture the interrupt signals properly. For the platform that has only one clock domain, this step can be skipped.***

9. Click ***Run Connection Automation***  

10. Leave the default values for Master interface and Bridge IP.
   - Master interface default is ***/zynq_ultra_ps_e_0/M_AXI_HPM0_LPD***.
   - Bridge IP default is New AXI interconnect.
11. Expand output interface Interrupt of ***axi_intc_0*** to show the port irq, connect this irq port to ***zynq_ultra_ps_e_0.pl_ps_irq0***
12. Setup **PFM_IRQ** property by typing following command in Vivado console:<br />
```set_property PFM.IRQ {intr {id 0 range 32}} [get_bd_cells /axi_intc_0]```
***The IPI design connection would like below:***
![ipi_fully_connection.png](images/ipi_fully_connection.png)


### Configuring Platform Interface Properties
1. Click ***Window->Platform interfaces***, and then click ***Enable platform interfaces*** link to open the ***Platform Interfaces*** Window.

2. Select ***Platform-system->zynq_ultra_ps_e_0->S_AXI_HP0_FPD***, in ***Platform interface Properties*** tab enable the ***Enabled*** option like below:<br />
    ![enable_s_axi_hp0_fpd.png](images/enable_s_axi_hp0_fpd.png)

3. Select ***Options*** tab, set ***memport*** to ```S_AXI_HP``` and set ***sptag*** to ```HP0``` like below:
    ![set_s_axi_hp0_fpd_options.png](images/set_s_axi_hp0_fpd_options.png)

4. Do the same operations for ***S_AXI_HP1_FPD, S_AXI_HP2_FPD, S_AXI_HP3_FPD, S_AXI_HPC0_FPD, S_AXI_HPC1_FPD*** and set ***sptag*** to ```HP1```, ```HP2```, ```HP3```, ```HPC0```, ```HPC1```. And be noticed that for HPC0/HPC1 ports the ***memport*** is set to ```S_AXI_HPC``` in default, but actually we would use these ports without data coherency function enabled to get a high performance. So please modify it into ```S_AXI_HP``` manually.<br />
    ![set_s_axi_hpc0_fpd_options.png](images/set_s_axi_hpc0_fpd_options.png)<br />

5. Enable the M01_AXI ~ M08_AXI ports of ps8_0_axi_periph IP(The AXI Interconnect between M_AXI_HPM0_LPD and axi_intc_0), and set these ports with the same ***sptag*** name to ```HPM0_LPD``` and ***memport*** type to ```M_AXI_GP```

6. Enable the ***M_AXI_HPM0_FPD*** and ***M_AXI_HPM1_FPD*** ports, set ***sptag*** name to ```HPM0_FPD```, ```HPM1_FPD``` and ***memport*** to ```M_AXI_GP```.

***Note: Fast Track:*** A Vivado project script ***step1_vivado/zcu104_custom_platform.tcl*** is provided. You can re-create the Vivado project by selecting ***Tools -> Run Tcl Script...*** in Vivado and select this file.

***Now we have enabled AXI master/slave interfaces that can be used for Vitis tools on the platform***

### Export Hardware XSA
1. Validate the block design by clicking ***Validate Design*** button
2. In ***Source*** tab, right click ***system.bd***, select ***Create HDL Wrapper...*** 
3. Select ***Let Vivado manage wrapper and auto-update***. Click OK to generate wrapper for block design.
4. Select ***Generate Block Design*** from Flow Navigator
5. Select ***Synthesis Options*** to ***Global*** and click ***Generate***. This will skip IP synthesis.
6. Click menu ***File -> Export -> Export Hardware*** to Export Platform from Vitis GUI
7. Select Platform Type: ***Expandable***
8. Select Platform Stage: ***Pre-synthesis***
9. Input Platform Properties, for example<br />Name: zcu104_custom_platform<br />Vendor: xilinx<br />Board: zcu104<br />Version: 0.0<br />Description: This platform provides high PS DDR bandwidth and three clocks: 100Mhz, 200MHz and 400MHz.
10. Fill in XSA file name: ***zcu104_custom_platform***, export directory: ***<you_vivado_design_dir>***
11. Click OK. zcu104_custom_platform.xsa will be generated.
12. Alternatively, the above export can be done in Tcl scripts

```tcl
# Setting platform properties
set_property platform.default_output_type "sd_card" [current_project]
set_property platform.design_intent.embedded "true" [current_project]
set_property platform.design_intent.server_managed "false" [current_project]
set_property platform.design_intent.external_host "false" [current_project]
set_property platform.design_intent.datacenter "false" [current_project]
# Write pre-synthesis expandable XSA
write_hw_platform -unified ./zcu104_custom_platform.xsa
# Or uncomment command below to write post-implementation expandable XSA
# write_hw_platform -unified -include_bit ./zcu104_custom_platform.xsa
```

***Now we finish the Hardware platform creation flow, then we should go to the Software platform creation***

## Step 2: Create the Software Components with PetaLinux

A Vitis platform requires software components. Xilinx provides common software images for quick evaluation. Here since we'd like to do more customization, we'll use the PetaLinux tools to create the Linux image and sysroot with XRT support. Yocto or third-party Linux development tools can also be used as long as they produce the same Linux output products as PetaLinux. 

### PetaLinux Project Settings

1. Setup PetaLinux environment: `source <petaLinux_tool_install_dir>/settings.sh`

2. Create a PetaLinux project named ***zcu104_custom_plnx*** and configure the hw with the XSA file we created before:

    ```
    petalinux-create --type project --template zynqMP --name zcu104_custom_plnx
    cd zcu104_custom_plnx
    petalinux-config --get-hw-description=<you_vivado_design_dir>
    ```

3. A petalinux-config menu would be launched, select ***DTG Settings->MACHINE_NAME***, modify it to ```zcu104-revc```.<br />
    ***Note: If you are using a Xilinx development board it is recommended to modify the machine name so that the board configurations would be involved in the DTS auto-generation. Otherwise you would need to configure the associated settings(e.g. the PHY information DTS node) by yourself manually.***<br />



### Customize Root File System, Kernel, Device Tree and U-boot

1. Add user packages by appending the CONFIG_x lines below to the ***<your_petalinux_project_dir>/project-spec/meta-user/conf/user-rootfsconfig*** file.

   ***Note: This step is not a must but it makes it easier to find and select all required packages in next step.***

   Packages for base XRT support:

    ```
   CONFIG_packagegroup-petalinux-xrt
    ```

   Packages for easy system management

    ```
   CONFIG_dnf
   CONFIG_e2fsprogs-resize2fs
   CONFIG_parted
    ```

    Packages for Vitis-AI dependencies support:

    ```
   CONFIG_packagegroup-petalinux-vitisai
    ```

   Packages for natively building Vitis AI applications on target board: 

    ```
   CONFIG_packagegroup-petalinux-self-hosted
   CONFIG_cmake 
   CONFIG_packagegroup-petalinux-vitisai-dev
   CONFIG_xrt-dev
   CONFIG_opencl-clhpp-dev
   CONFIG_opencl-headers-dev
   CONFIG_packagegroup-petalinux-opencv
   CONFIG_packagegroup-petalinux-opencv-dev
    ```

    Packages for running Vitis-AI demo applications with GUI

    ```
    CONFIG_mesa-megadriver
    CONFIG_packagegroup-petalinux-x11
    CONFIG_packagegroup-petalinux-v4lutils
    CONFIG_packagegroup-petalinux-matchbox
    ```

2. Run ```petalinux-config -c rootfs``` and select ***user packages***, select name of rootfs all the libraries listed above, save and exit.
    ![petalinux_rootfs.png](images/petalinux_rootfs.png)

3. Enable OpenSSH and disable dropbear 
    Dropbear is the default SSH tool in Vitis Base Embedded Platform. If OpenSSH is used to replace Dropbear, the system could achieve 4x times faster data transmission speed (tested on 1Gbps Ethernet environment). Since Vitis-AI applications may use remote display feature to show machine learning results, using OpenSSH can improve the display experience. 
   a) Run ```petalinux-config -c rootfs``` 
   b) Go to ***Image Features***. 
   c) Disable ***ssh-server-dropbear*** and enable ***ssh-server-openssh***. 
   ![ssh_settings.png](images/ssh_settings.png)
   
d) Go to ***Filesystem Packages-> misc->packagegroup-core-ssh-dropbear*** and disable ***packagegroup-core-ssh-dropbear***.
   
e) Go to ***Filesystem Packages  -> console  -> network -> openssh*** and enable ***openssh***, ***openssh-sftp-server***, ***openssh-sshd***, ***openssh-scp***.
    
4. In rootfs config go to ***Image Features*** and enable ***package-management*** and ***debug_tweaks*** option, store the change and exit.

5. Disable CPU IDLE in kernel config.

   CPU IDLE would cause CPU IDLE when JTAG is connected. So it is recommended to disable the selection during project development phase. It can be enabled for production to save power. 
   a) Type ```petalinux-config -c kernel``` 
   b) Ensure the following are ***TURNED OFF*** by entering 'n' in the [ ] menu selection for:

   - ***CPU Power Mangement > CPU Idle > CPU idle PM support***
       - ***CPU Power Management > CPU Frequency scaling > CPU Frequency scaling***

6. Update the Device tree.

    Append the following contents to the ***project-spec/meta-user/recipes-bsp/device-tree/files/system-user.dtsi*** file. 

    - ***zyxclmm_drm*** node is required by zocl driver, which is a part of XRT.
    - ***axi_intc_0*** node defines 32 interrupt inputs. This can not be inferred by the hardware settings in Vivado.
    - ***sdhci1*** node decreases SD Card speed for better card compatibility on ZCU104 board. This only relates to ZCU104. It's not a part of Vitis acceleration platform requirements.

    ***Note***: an example file is provided in ***ref_files/step2_petalinux/system-user.dtsi***.
    ```
    &amba {
        zyxclmm_drm {
            compatible = "xlnx,zocl";
            status = "okay";
            interrupt-parent = <&axi_intc_0>;
            interrupts = <0  4>, <1  4>, <2  4>, <3  4>,
                     <4  4>, <5  4>, <6  4>, <7  4>,
                     <8  4>, <9  4>, <10 4>, <11 4>,
                     <12 4>, <13 4>, <14 4>, <15 4>,
                     <16 4>, <17 4>, <18 4>, <19 4>,
                     <20 4>, <21 4>, <22 4>, <23 4>,
                     <24 4>, <25 4>, <26 4>, <27 4>,
                     <28 4>, <29 4>, <30 4>, <31 4>;
        };
    };
    
    &axi_intc_0 {
          xlnx,kind-of-intr = <0x0>;
          xlnx,num-intr-inputs = <0x20>;
          interrupt-parent = <&gic>;
          interrupts = <0 89 4>;
    };
    
    &sdhci1 {
          no-1-8-v;
          disable-wp;
    };
    
    ```




7. Add EXT4 rootfs support

    Since Vitis-AI software stack is not included in PetaLinux yet, they need to be installed after PetaLinux generates rootfs. PetaLinux uses initramfs format for rootfs by default, it can't retain the rootfs changes in run time. To make the root file system retain changes, we'll use EXT4 format for rootfs in second partition while keep the first partition FAT32 to store boot.bin file.

    Run `petalinux-config`, go to ***Image Packaging Configuration***, select ***Root File System Type*** as ***EXT4***, and append `ext4 ext4.gz` to ***Root File System Formats***.

    ![](images/petalinux_root_filesystem_type.png)

    ![](./images/petalinux_add_rootfs_types.png)

### Build Image and Prepare for Platform Packaging

We would store all the necessary files for Vitis platform creation flow. Here we name it ```zcu104_custom_pkg ```. Then we create a pfm folder inside.

1. From any directory within the PetaLinux project, build the PetaLinux project.

   ```
   petalinux-build
   ```

   

2. Copy the generated Linux software boot components from ***<your_petalinux_dir>/images/linux directory*** to the ***<full_pathname_to_zcu104_custom_pkg>/pfm/boot*** directory to prepare for running the Vitis platform packaging flow:

    - zynqmp_fsbl.elf: ***rename as fsbl.elf*** as a workaround of a Vitis known issue.
    - pmufw.elf
    - bl31.elf
    - u-boot.elf

Note: These files are the sources of creating BOOT.BIN.

3. Add a BIF file (linux.bif) to the ***<full_pathname_to_zcu104_custom_pkg>/pfm/boot*** directory with the contents shown below. The file names should match the contents of the boot directory. The Vitis tool expands these pathnames relative to the sw directory of the platform at v++ link time or when generating an SD card. However, if the bootgen command is used directly to create a BOOT.BIN file from a BIF file, full pathnames in the BIF are necessary. Bootgen does not expand the names between the <> symbols.<br />
```
/* linux */
 the_ROM_image:
 {
 	[fsbl_config] a53_x64
 	[bootloader] <fsbl.elf>
 	[pmufw_image] <pmufw.elf>
 	[destination_device=pl] <bitstream>
 	[destination_cpu=a53-0, exception_level=el-3, trustzone] <bl31.elf>
 	[destination_cpu=a53-0, exception_level=el-2] <u-boot.elf>
 }
```

4. Prepare image directory. Contents in this directory will be packaged to FAT32 partition by v++ package tool.

    a) Copy the generated Linux software components from ***<your_petalinux_dir>/images/linux directory*** to the ***<full_pathname_to_zcu104_custom_pkg>/pfm/image*** directory. 

    - boot.scr: script for u-boot initialization
    - system.dtb: device tree file for Linux to boot

    b) Copy ***init.sh*** and ***platform_description.txt*** from ***ref_files/step3_pfm*** to ***<full_pathname_to_zcu104_custom_pkg>/pfm/image*** directory.

    - init.sh will set environment variable XILINX_XRT for XRT and copy platform_desc.txt to /etc/xocl.txt
    - platform_desc.txt has the platform name. XRT will check platform name before loading xclbin file.

5. Create a sysroot self-installer for the target Linux system

    ```
    petalinux-build --sdk
    ```

6. Install sysroot: type ```./images/linux/sdk.sh``` to install PetaLinux SDK, provide a full pathname to the output directory ***zcu104_custom_pkg/pfm*** (This is an example ) and confirm.<br />

  We would install Vitis AI library and DNNDK into this rootfs in the future.

***Note: Now HW platform and SW platform are all generated. Next we would package the Vitis Platform.***

## Step 3: Create the Vitis Platform

First we create a Vitis platform project with the XSA file generated by Vivado from Step 1.

1. Source Vitis and XRT settings

    ```
    source <Vitis_Install_Directory>/settings64.sh
    source /opt/xilinx/xrt/setup.sh
    ```

2. Go to the ***zcu104_custom_pkg*** folder you created: 

    ```
    cd <full_pathname_to_zcu104_custom_pkg>
    ```

3. Launch Vitis by typing ```vitis``` in the console.

4. Select ***zcu104_custom_pkg*** folder as workspace directory.

5. In the Vitis IDE, select ***File > New > Platform Project*** to create a platform project.<br />

6. Enter the project name. For this example, type ```zcu104_custom```, click ***Next***.

7. In the Platform page, 

    a) Click ***Browse*** button, select the XSA file generated by the Vivado. In this case, it is located in ```vivado/zcu104_custom_platform.xsa```.
    b) Set the operating system to ***linux***.

    c) Set the processor to ***psu_cortexa53***.

    d) Architecture: ***64-bit***

    e) ***Uncheck*** option ***Generate boot components***, because we'll use PetaLinux generated boot components.

    f) Click ***Finish***.

Next we setup software settings in Platform Settings view.

1. In the Platform Settings view, observe the following:<br />
   - The name of the Platform Settings view matches the platform project name of ***zcu104_custom***.<br />
   - A psu_cortexa53 device icon is shown, containing a Linux on psu_cortexa53 domain.<br />
2. Click the ***linux on psu_cortexa53*** domain, browse to the locations and select the directory or file needed to complete the dialog box for the following:

	- ***Bif file***: Browse to ***zcu104_custom_pkg/pfm/boot/linux.bif*** file and click OK.
	- ***Boot Components Direcotory***: Browse to ***zcu104_custom_pkg/pfm/boot*** and click OK.
	- ***Linux Image Directory***: Browse to ***zcu104_custom_pkg/pfm/image*** and click OK.

![vitis_linux_config.png](images/vitis_linux_config.png)
11. Click ***zcu104_custom*** project in the Vitis Explorer view, click the ***Build*** button to generate the platform.
![](images/build_vitis_platform.png)

***Note: The generated platform is placed in the export directory. BSP and source files are also provided for re-building the FSBL and PMU if desired and are associated with the platform. The platform is ready to be used for application development.***

![](./images/vitis_platform_output.png)



## Step 4: Test the Platform

### Test 1: Read Platform Info

With Vitis environment setup, platforminfo tool can report XPFM platform information.

```
# in zcu104_custom_pkg directory
platforminfo ./zcu104_custom/export/zcu104_custom/zcu104_custom.xpfm
==========================
Basic Platform Information
==========================
Platform:           zcu104_custom
File:               /scratch/rickys/work/idt_platform/zcu104_custom_pkg/zcu104_custom/export/zcu104_custom/zcu104_custom.xpfm
Description:        
zcu104_custom
    

=====================================
Hardware Platform (Shell) Information
=====================================
Vendor:                           xilinx
Board:                            zcu104_custom_platform
Name:                             zcu104_custom_platform
Version:                          0.0
Generated Version:                2020.1
Software Emulation:               1
Hardware Emulation:               0
FPGA Family:                      zynquplus
FPGA Device:                      xczu7ev
Board Vendor:                     xilinx.com
Board Name:                       xilinx.com:zcu104:1.1
Board Part:                       xczu7ev-ffvc1156-2-e
Maximum Number of Compute Units:  60

=================
Clock Information
=================
  Default Clock Index: 0
  Clock Index:         2
    Frequency:         100.000000
  Clock Index:         0
    Frequency:         200.000000
  Clock Index:         1
    Frequency:         400.000000

==================
Memory Information
==================
  Bus SP Tag: HP0
  Bus SP Tag: HP1
  Bus SP Tag: HP2
  Bus SP Tag: HP3
  Bus SP Tag: HPC0
  Bus SP Tag: HPC1
=======================
Feature ROM Information
=======================
=============================
Software Platform Information
=============================
Number of Runtimes:            1
Default System Configuration:  zcu104_custom
System Configurations:
  System Config Name:                      zcu104_custom
  System Config Description:               zcu104_custom
  System Config Default Processor Group:   linux_domain
  System Config Default Boot Image:        standard
  System Config Is QEMU Supported:         0
  System Config Processor Groups:
    Processor Group Name:      linux on psu_cortexa53
    Processor Group CPU Type:  cortex-a53
    Processor Group OS Name:   linux
  System Config Boot Images:
    Boot Image Name:           standard
    Boot Image Type:           
    Boot Image BIF:            zcu104_custom/boot/linux.bif
    Boot Image Data:           zcu104_custom/linux_domain/image
    Boot Image Boot Mode:      sd
    Boot Image RootFileSystem: 
    Boot Image Mount Path:     /mnt
    Boot Image Read Me:        zcu104_custom/boot/generic.readme
    Boot Image QEMU Args:      
    Boot Image QEMU Boot:      
    Boot Image QEMU Dev Tree:  
Supported Runtimes:
  Runtime: OpenCL
```

We can verify clock information and memory information are set as expected.



### Test 2: Run Vector Addition Application

Vector addition is the simplest acceleration PL kernel. Vitis can create this application automatically. Running this test can check the AXI control bus, memory interface and interrupt setting in platform are working properly.

#### Creating Vector Addition Application

1. Open Vitis workspace you were using before.<br />
2. Select ***File -> New -> Application Project***.<br />
3. Click ***next***<br />
4. Select ***zcu104_custom*** as platform, click ***next***.<br />
5. Name the project ***vadd***, click ***next***.<br />
6. Set Domain to ***linux on psu_cortexa53***, set ***Sys_root path*** to ```<full_pathname_to_zcu104_custom_pkg>/pfm/sysroots/aarch64-xilinx-linux```(as you created by running ***sdk.sh***), keep the ***Kernel Image*** setting in default and click ***next***.<br />
7. Select ***System Optimization Examples -> Vector Addition*** and click ***finish*** to generate the application.<br />
8. In the Explorer window double click the hello_dpu.prj file to open it, change the ***Active Build configuration*** from ***Emulation-SW*** to ***Hardware***.<br />
9. Select ***vadd_system*** in Explorer window and Click ***Build*** icon in toolbar.

#### Running Vector Addition Application

1. Copy ***zcu104_custom_pkg/vadd_system/Hardware/package/sd_card.img*** to local if Vitis is running on a remote server.

2. Write ***sd_card.img*** into SD Card with SD Card image writer applications like Etcher on Windows or dd on Linux.

3. Boot ZCU104 board with the SD card in SD boot mode.

4. Login with username ***root*** and password ***root***.

5. Go to auto mounted FAT32 partition

   ```bash
   cd /mnt/sd-mmcblk0p1
   ```

6. Initialize XRT running environment

   ```bash
   source ./init.sh
   ```

7. Run vadd appliation

   ```bash
   ./vadd vadd.xclbin
   ```

8. It should show program prints and XRT debug info.

   ```
   TEST PASSED
   ```

   

### Test 3: Run a DNNDK Demo

This test will run a simple DNNDK test application to test DPU function.

#### Prepare for the DPU Kernel

1. Download Vitis AI by calling command ```git clone https://github.com/Xilinx/Vitis-AI.git```.<br />
2. Navigate to the repository:```cd Vitis-AI```, set the tag to proper tag(here we use **v1.2**) by typing: ```git checkout v1.2```.<br />
3. If you don't want to destroy the TRD reference design. Copy ***DPU-TRD*** folder into another directory. For example I would copy that into my ***zcu104_custom_pkg*** folder: ```cp -r DPU-TRD ./zcu104_custom_pkg/```<br />
4. Source Vitis tools setting sh file: ```source <vitis install path>/Vitis/2020.1/settings64.sh```.<br />
5. Source XRT sh file:```source opt/xilinx/xrt/setup.sh```.<br />
6. Export ***PLATFORM_REPO_PATHS*** with the directory of the custom platform xpfm file which you created before so that it can be found by Vitis. Here in my project it would be: ```export PLATFORM_REPO_PATHS=<path_to/zcu104_custom_pkg/zcu104_custom/export/zcu104_custom>```. Remember now this custom platform name is ***zcu104_custom***.<br />
7. Navigate to the copy of the ***DPU-TRD*** folder, then go to the ***./prj/Vitis*** folder.<br />
There are 2 files can be used to modify the DPU settings: The ***config_file/prj_config*** file is for DPU connection in Vitis project and the ***dpu_conf.vh*** is for other DPU configurations. Here we would modify the ***prj_config*** so that 2 DPU cores are enabled. And then we modify ***dpu_conf.vh*** as [DPU-TRD readme](https://github.com/Xilinx/Vitis-AI/blob/v1.2/DPU-TRD/README.md) suggested.<br />
8. Modify the ***config_file/prj_config*** like below:<br />
```

[clock]

id=0:DPUCZDX8G_1.aclk
id=1:DPUCZDX8G_1.ap_clk_2
id=0:DPUCZDX8G_2.aclk
id=1:DPUCZDX8G_2.ap_clk_2

[connectivity]

sp=DPUCZDX8G_1.M_AXI_GP0:HPC0
sp=DPUCZDX8G_1.M_AXI_HP0:HP0
sp=DPUCZDX8G_1.M_AXI_HP2:HP1
sp=DPUCZDX8G_2.M_AXI_GP0:HPC1
sp=DPUCZDX8G_2.M_AXI_HP0:HP2
sp=DPUCZDX8G_2.M_AXI_HP2:HP3

[advanced]
misc=:solution_name=link
#param=compiler.addOutputTypes=sd_card

#param=compiler.skipTimingCheckAndFrequencyScaling=1

[vivado]
prop=run.impl_1.strategy=Performance_Explore
#param=place.runPartPlacer=0

```
​	Here clock ID 0 is 200MHz, clock ID 1 is 400MHz.

​	This file describes the link connections between DPU and the platform. It will be used by Vitis application in next step.

​	***Note***: an example of prj_config file is provided in ***ref_files/step4_test3/app_src***.

9. Modify ***dpu_conf.vh*** to enable URAM because ZU7EV device on ZCU104 board has URAM resources. Change from:<br />
```
`define URAM_DISABLE 
```
to<br />
```
`define URAM_ENABLE 
```

10. Generate the XO file by typing: ```make binary_container_1/dpu.xo DEVICE=zcu104_custom```.<br />
11. Verify if the XO file is generated here: ***<zcu104_custom_pkg directory>/DPU-TRD/prj/Vitis/binary_container_1/dpu.xo***.<br />

#### Create and Build a Vitis Application
1. Open Vitis workspace you were using before.<br />
2. Select ***File -> New -> Application Project***.<br />
3. Click ***next***<br />
4. Select ***zcu104_custom*** as platform, click ***next***.<br />
5. Name the project ```hello_dpu```, click ***next***.<br />
5. Set Domain to ***linux on psu_cortexa53***
7. Set ***Sys_root path*** to ```<full_pathname_to_zcu104_custom_pkg>/pfm/sysroots/aarch64-xilinx-linux```(as you created by running ***sdk.sh***)
8. Set the ***Kernel Image*** to ***zcu104_custom_plnx/images/linux/Image*** 
9. Set Root Filesystem to ***zcu104_custom_plnx/images/linux/rootfs.ext4*** and click ***next***.<br />
10. Select ***System Optimization Examples -> Empty application*** and click ***finish*** to generate the application.<br />
11. Right click on the ***src*** folder under your ***hello_dpu*** application  in the Explorer window, and select "Import Sources"
      ![import_sources.png](images/import_sources.png)<br /><br />
12. Choose from directory ***<zcu104_custom_pkg directory>/DPU-TRD/prj/Vitis/binary_container_1/*** as the target location, and import the ***dpu.xo*** file that we just created.<br />
13. Import sources again, and add all files from ***ref_files/step4_test3/app_src*** folder provided by this Git repository, including prj_config.
14. In the Explorer window double click the hello_dpu.prj file to open it, change the ***Active Build configuration*** from ***Emulation-SW*** to ***Hardware***.<br />
15. Under Hardware Functions, click the lightning bolt logo to ***Add Hardware Function***.<br />
    ![add_hardware_function.png](images/add_hardware_function.png)<br /><br />
16. Select the "DPUCZDX8G" included as part of the dpu.xo file that we included earlier.<br />
17. Click on binary_container_1 to change the name to dpu.<br />
18. Click on ***DPUCZDX8G*** and change the ***Compute Units*** from ```1``` to ```2``` because we have 2 dpu cores involved.<br />
19. Right click on "dpu", select ***Edit V++ Options***, add ```--config ../src/prj_config -s``` as ***V++ Options***, then click ***OK***.<br />
20. Go back to the ***Explorer*** window, right click on the ***hello_dpu*** project folder select ***C/C++ Building Settings***.<br />
21. In ***Properties for hello_dpu*** dialog box, select ***C/C++ Build->Settings->Tool Settings->GCC Host Linker->Libraries***
    , click the green "+" to add the following libraries:
```
opencv_core
opencv_imgcodecs
opencv_highgui
opencv_imgproc
opencv_videoio
n2cube
hineon
```
18. In the same page, Check the ***Library search path*** to makesure the ```${SYSROOT}/usr/lib/``` is added, click ***Apply***<br />
![vitis_lib_settings.png](images/vitis_lib_settings.png)<br /><br />
19. Then go to ***C/C++ Build->Settings->Tool Settings->GCC Host Compiler->Includes***, remove the HLS include directory and add ```${SYSROOT}/usr/include/``` like below, then click ***Apply and Close*** to save the changes.<br />
![vitis_include_settings.png](images/vitis_include_settings.png)These steps are used to make sure your application can call libs in rootfs directly on Vitis application build***
21. Right click the ***hello_dpu*** project folder and select ***Build Project***<br />

#### Prepare the Network Deployment File

1. Find HWH file from your Vitis application folder ***hello_dpu/Hardware/dpu.build/link/vivado/vpl/prj/prj.srcs/sources_1/bd/system/hw_handoff/system.hwh***<br />
Or go to your Vitis application folder use command ```find -name *.hwh``` to search for the file.<br />
2. Copy the ***ref_files/step4_test3/Tool-Example*** folder provided by this Github repository to your Vitis AI download directory.<br />
3. Copy this HWH file into ***<Vitis-AI-download_directory>/Tool-Example*** folder.<br />
4. Go to ***<Vitis-AI-download_directory>*** folder and launch the docker.
```
./docker_run.sh xilinx/vitis-ai:latest
```

5. Use following command to activate TensorFlow tool conda environment:<br />
```
conda activate vitis-ai-tensorflow
```
6. Go to ***/workspace/Tool-Example*** folder and run ```dlet -f ./system.hwh```.<br />
You should get the running log like below:
```
$ dlet -f ./system.hwh 
[DLet]Generate DPU DCF file dpu-06-18-2020-12-00.dcf successfully.<br />
```
7. Open the ***arch.json*** file and make sure the ***"dcf"*** parameter is set with the name you got on the previous step:<br />
```"dcf"      : "./dpu-06-18-2020-12-00.dcf",```<br />
8. Run command ```sh download_model.sh``` to download the Xilinx Model Zoo files for resnet-50.<br />
9. Run command ```sh custom_platform_compile.sh```, you'll get the result at ***tf_resnetv1_50_imagenet_224_224_6.97G/vai_c_output_ZCU104/dpu_resnet50_0.elf*** .<br />
10. Copy that file to the ***src*** folder of Vitis application ***hello_dpu***<br />
11. Right click on the ***hello_dpu*** project folder in Vitis select ***C/C++ Building Settings**.<br />
12. In ***Properties for Hello_DPU*** dialog box, select ***C/C++ Build->Settings->Tool Settings->GCC Host Linker->Miscellaneous->Other objects***, add a new object: ```${workspace_loc:/${ProjName}/src/dpu_resnet50_0.elf}```, click ***Apply and Close***.<br />
13. Right click the ***hello_dpu*** project folder and select ***Build Project***<br />
***Now you should get an updated hello_dpu with a size of about 20MB(the ConvNet model is involved).***

#### Run Application on Board
1. If you have run Test 2 vadd application, copy all the files from ***sd_card folder*** inside your Vitis application like ***<hello_dpu_application_directory>/Hardware/sd_card/*** to SD card FAT32 partition. It's not necessary to write sd_card.img again because the EXT4 partition is the same.

   If you haven't run Test 2 vadd application, please copy ./hello_dpu_system/Hardware/package/sd_card.img to local and write it to SD card with tools like Etcher on Windows or dd on Linux.

2. Download dnndk installer [vitis-ai_v1.2_dnndk.tar.gz](https://www.xilinx.com/bin/public/openDownload?filename=vitis-ai_v1.2_dnndk.tar.gz) , dnndk sample image package [vitis-ai_v1.2_dnndk_sample_img.tar.gz](https://www.xilinx.com/bin/public/openDownload?filename=vitis-ai_v1.2_dnndk_sample_img.tar.gz)  and [DPU specific board optimization scripts](https://github.com/Xilinx/Vitis-AI/raw/b3773aa2f21ca9afaa9656ce7ec3f74242eb74f1/DPU-TRD/app/dpu_sw_optimize.tar.gz
   cp ) to host and copy them to FAT32 partition on SD card. For more information about these packages, please refer to  [DNNDK example readme file](https://github.com/Xilinx/Vitis-AI/blob/v1.2/mpsoc/README.md)

3. Set ZCU104 to SD boot mode and boot up the board, connect the board with serial port.<br />

4. Connect SSH:<br />
   a) Connect Ethernet cable. 

   b) Run ```ifconfig``` on ZCU104 board to get the IP address, here we take ```172.16.75.189``` as example.<br />c) Using SSH terminal to connect ZCU104 with SSH: ```ssh -x root@172.16.75.189```, or use MobaXterm in Windows.<br />

5. Go to auto-mounted SD card partition /mnt/sd-mmcblk0p1 folder and copy these files to home directory
    ```
    cd /mnt/sd-mmcblk0p1
    cp dpu_sw_optimize.tar.gz vitis-ai_v1.2_dnndk.tar.gz vitis-ai_v1.2_dnndk_sample_img.tar.gz ~
    ```
    
5. Run DPU Software Optimization

   ```bash
   cd ~
   tar -xzf dpu_sw_optimize.tar.gz
   cd dpu_sw_optimize/zynqmp/
   ./zynqmp_dpu_optimize.sh
   ```
   
   It will show the optimization results
   
   ```
   Auto resize ext4 partition ...[✔]
   Start QoS config ...[✔]
   Config PMIC irps5401 ...Successful[✔]
   ```
   
   - Auto resize scripts expands the EXT4 partition to rest of the SD card so that we can store more contents.
   
   - QoS config makes AXI interface for DPU has higher priority.
   
   - PMIC config makes ZCU104 can use more power when running Vitis-AI applications.
   
7. Install DNNDK package like below:<br />

   ```
   tar -zxvf vitis-ai_v1.2_dnndk.tar.gz
   cd vitis-ai_v1.2_dnndk/
   ./install.sh
   ```
   ***install.sh*** copies ***dpu.xclbin*** from FAT32 partition to /usr/lib because DNNDK requires xclbin to be placed in this location.  

   ***Note: Vitis-AI Library has the similar installation method. Please refer to Vitis-AI user guide for more info.*** 

6. Extract vitis_ai_dnndk_samples and put hello_dpu into it:
    ```
    cd ~
    tar -zxvf vitis-ai_v1.2_dnndk_sample_img.tar.gz
    cd vitis_ai_dnndk_samples
    mkdir test
    cd test
    cp /mnt/sd-mmcblk0p1/hello_dpu ./
    ./hello_dpu
    ```
	***We store the hello_dpu to vitis_ai_dnndk_samples/test folder to suit the relative path in my code, you can do that according to your code context. The hello_dpu is generated in Vitis application build and was copied to sd card from previous operation.***<br />

7. You should see the result like below:<br />
![test_result.PNG](images/test_result.PNG)

## Reference

- https://www.xilinx.com/html_docs/xilinx2020_1/vitis_doc/index.html
- https://github.com/Xilinx/Vitis-AI
- https://github.com/Xilinx/Vitis_Embedded_Platform_Source
- https://github.com/Xilinx/Vitis-AI-Tutorials/tree/Vitis-AI-Custom-Platform
- https://github.com/Xilinx/Edge-AI-Platform-Tutorials/tree/3.1/docs/DPU-Integration

***Note: If you would like to try with one click creating VAI platform flow it is recommended to try with the official base platform source code for*** [zcu102_dpu](https://github.com/Xilinx/Vitis_Embedded_Platform_Source/tree/master/Xilinx_Official_Platforms/zcu102_base) ***and*** [zcu104_dpu](https://github.com/Xilinx/Vitis_Embedded_Platform_Source/tree/master/Xilinx_Official_Platforms/zcu104_base)***.*** 

### More Information about Install and Set Vitis and XRT Environment

- [Setting up the Vitis environment](https://www.xilinx.com/html_docs/xilinx2020_1/vitis_doc/settingupvitisenvironment.html)
- [Installing Xilinx Runtime](https://www.xilinx.com/html_docs/xilinx2020_1/vitis_doc/pjr1542153622642.html)

