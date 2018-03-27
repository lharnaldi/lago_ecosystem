#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <poll.h>
#include <signal.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>

#include <string.h>
#include <time.h>
#include <math.h>
#include <sys/time.h>
//#include <fstream>
//#include <iostream>
//#include <vector>

#include "defs.h"

//Globals
int int_fd, cfg_fd, sts_fd, xadc_fd;
void *int_ptr, *cfg_ptr, *sts_ptr, *xadc_ptr;
int dev_size;
int interrupted = 0;

int fGetReg, fGetRegSet, fGetPT, fGetGPS, fPutReg, fPutRegSet,
		fToFile, fToStdout, fFile, fCount, fByte, fData, fFirstTime=1,
		fshowversion;

char scAction[MAXCHRLEN], scRegister[MAXCHRLEN], scReg[MAXCHRLEN],
		 scDvc[MAXCHRLEN] = "Nexys2", scFile[MAXCHRLEN], scCurrentFile[MAXCHRLEN],
		 scCount[MAXCHRLEN], scByte[MAXCHRLEN], scData[MAXCHRLEN], scCurrentMetaData[MAXCHRLEN];


typedef struct ldata {
				int trigg_1;   // trigger level ch1
				int trigg_2;   // trigger level ch2
				int strigg_1;  // sub-trigger level ch1
				int strigg_2;  // sub-trigger level ch2
				int nsamples;  // N of samples
				int time;
				double latitude;
				char lat;
				double longitude;
				char lon;
				uint8_t quality;
				uint8_t satellites;
				double altitude;
} ldata_t;

void signal_handler(int sig)
{
				interrupted = 1;
}

inline void dev_write(void *dev_base, unsigned int offset, unsigned int value)
{
				*((volatile unsigned *)(dev_base + offset)) = value;
}

inline unsigned int dev_read(void *dev_base, unsigned int offset)
{
				return *((volatile unsigned *)(dev_base + offset));
}

int wait_for_interrupt(int fd_int, void *dev_ptr) 
{
				static unsigned int count = 0, bntd_flag = 0, bntu_flag = 0;
				int flag_end=0;
				int pending = 0;
				int reenable = 1;
				unsigned int reg;
				unsigned int value;
				uint32_t info = 1; /* unmask */

				ssize_t nb = write(fd_int, &info, sizeof(info));
				if (nb != (ssize_t)sizeof(info)) {
								perror("write");
								close(fd_int);
								exit(EXIT_FAILURE);
				}

				// block (timeout for poll) on the file waiting for an interrupt 
				struct pollfd fds = 
				{
								.fd = fd_int,
								.events = POLLIN,
				};

				int ret = poll(&fds, 1, 1000);
				printf("ret is : %d\n", ret);
				if (ret >= 1) {
								nb = read(fd_int, &info, sizeof(info));
								if (nb == (ssize_t)sizeof(info)) {
												/* Do something in response to the interrupt. */
												value = dev_read(dev_ptr, XIL_AXI_INTC_IPR_OFFSET);
												if ((value & 0x00000001) != 0) {
																dev_write(dev_ptr, XIL_AXI_INTC_IAR_OFFSET, 1);
																printf("Interrupt #%u!\n", info);
												}
								} else {
												perror("poll()");
												close(fd_int);
												exit(EXIT_FAILURE);
								}
				}

				return ret;
}

unsigned int get_memory_size(char *sysfs_path_file)
{
				FILE *size_fp;
				unsigned int size;

				// open the file that describes the memory range size that is based on the
				// reg property of the node in the device tree

				size_fp = fopen(sysfs_path_file, "r");

				if (!size_fp) {
								printf("unable to open the uio size file\n");
								exit(-1);
				}

				// get the size which is an ASCII string such as 0xXXXXXXXX and then be stop
				// using the file

				fscanf(size_fp, "0x%08X", &size);
				fclose(size_fp);

				return size;
}

//void *thread_isr(void *p) 
//{
//  wait_for_interrupt(fd, dev_ptr);
//
//}

int int_init(){
				char *uiod = "/dev/uio0";

				printf("Initializing INTC device...\n");

				// open the UIO device file to allow access to the device in user space
				int_fd = open(uiod, O_RDWR);
				if (int_fd < 1) {
								printf("Invalid UIO device file:%s.\n", uiod);
								return -1;
				}

				dev_size = get_memory_size("/sys/class/uio/uio0/maps/map0/size");

				// mmap the INTC device into user space
				int_ptr = mmap(NULL, dev_size, PROT_READ|PROT_WRITE, MAP_SHARED, int_fd, 0);
				if (int_ptr == MAP_FAILED) {
								printf("mmap call failure.\n");
								return -1;
				}


				// steps to accept interrupts -> as pg. 26 of pg099-axi-intc.pdf
				//1) Each bit in the IER corresponding to an interrupt must be set to 1.
								dev_write(int_ptr,XIL_AXI_INTC_IER_OFFSET, 1);
				//2) There are two bits in the MER. The ME bit must be set to enable the
				//interrupt request outputs.
								dev_write(int_ptr,XIL_AXI_INTC_MER_OFFSET, XIL_AXI_INTC_MER_ME_MASK | XIL_AXI_INTC_MER_HIE_MASK);
				//				dev_write(dev_ptr,XIL_AXI_INTC_MER_OFFSET, XIL_AXI_INTC_MER_ME_MASK);

				//The next block of code is to test interrupts by software
				//3) Software testing can now proceed by writing a 1 to any bit position
				//in the ISR that corresponds to an existing interrupt input.
				       dev_write(int_ptr,XIL_AXI_INTC_IPR_OFFSET, 1);

				//        for(a=0; a<10; a++)
				//        {
				//         wait_for_interrupt(fd, dev_ptr);
				//         dev_write(dev_ptr,XIL_AXI_INTC_ISR_OFFSET, 1); //regenerate interrupt
				//        }
				//
				//

				return 0;
}

int cfg_init(){
				char *uiod = "/dev/uio1";

				printf("Initializing CFG device...\n");

				// open the UIO device file to allow access to the device in user space
				cfg_fd = open(uiod, O_RDWR);
				if (cfg_fd < 1) {
								printf("Invalid UIO device file:%s.\n", uiod);
								return -1;
				}

				dev_size = get_memory_size("/sys/class/uio/uio1/maps/map0/size");

				// mmap the cfgC device into user space
				cfg_ptr = mmap(NULL, dev_size, PROT_READ|PROT_WRITE, MAP_SHARED, cfg_fd, 0);
				if (cfg_ptr == MAP_FAILED) {
								printf("mmap call failure.\n");
								return -1;
				}

				return 0;
}

int sts_init(){
				char *uiod = "/dev/uio2";

				printf("Initializing STS device...\n");

				// open the UIO device file to allow access to the device in user space
				sts_fd = open(uiod, O_RDWR);
				if (sts_fd < 1) {
								printf("Invalid UIO device file:%s.\n", uiod);
								return -1;
				}

				dev_size = get_memory_size("/sys/class/uio/uio2/maps/map0/size");

				// mmap the STS device into user space
				sts_ptr = mmap(NULL, dev_size, PROT_READ|PROT_WRITE, MAP_SHARED, sts_fd, 0);
				if (sts_ptr == MAP_FAILED) {
								printf("mmap call failure.\n");
								return -1;
				}

				return 0;
}

int xadc_init(){
				char *uiod = "/dev/uio3";

				printf("Initializing XADC device...\n");

				// open the UIO device file to allow access to the device in user space
				xadc_fd = open(uiod, O_RDWR);
				if (xadc_fd < 1) {
								printf("Invalid UIO device file:%s.\n", uiod);
								return -1;
				}

				dev_size = get_memory_size("/sys/class/uio/uio3/maps/map0/size");

				// mmap the XADC device into user space
				xadc_ptr = mmap(NULL, dev_size, PROT_READ|PROT_WRITE, MAP_SHARED, xadc_fd, 0);
				if (xadc_ptr == MAP_FAILED) {
								printf("mmap call failure.\n");
								return -1;
				}

				return 0;
}

void show_usage(char *progname) {
				if (fshowversion) {
								printf("LAGO ACQUA BRC v%dr%d data v%d\n",VERSION,REVISION,DATAVERSION);
				} else {
								printf("\n\tThe LAGO ACQUA suite\n");
								printf("\tData acquisition system for the LAGO BRC electronic\n");
								printf("\t(c) 2012-Today, The LAGO Project, http://lagoproject.org\n");
								printf("\t(c) 2012, LabDPR, http://labdpr.cab.cnea.gov.ar\n");
								printf("\n\tThe LAGO Project, lago@lagoproject.org\n");
								printf("\n\tDPR Lab. 2012\n");
								printf("\tH. Arnaldi, lharnaldi@gmail.com - H. Asorey, asoreyh@gmail.com\n");
								printf("\t%s v%dr%d comms soft\n\n",EXP,VERSION,REVISION);
								printf("Usage: %s <action> <register> <value> [options]\n", progname);

								printf("\n\tActions:\n");
								//  printf("\t-r\t\t\t\tGet a single register value\n");
								//  printf("\t-p\t\t\t\tPut a value into a single register\n");
								printf("\t-a\t\t\t\tGet all registers status\n");
								printf("\t-s\t\t\t\tSet registers\n");
								printf("\t-f\t\t\t\tStart DAQ and save data to file\n");
								printf("\t-o\t\t\t\tStart DAQ and send data to stdout\n");
								printf("\t-g\t\t\t\tGet GPS data\n");
								printf("\t-t\t\t\t\tGet Pressure and Temperature data\n");
								printf("\t-v\t\t\t\tShow DAQ version\n");

								printf("\n\tRegisters:\n");
								printf("\tt1, t2, t3\t\t\tSpecify triggers 1, 2 and 3\n");
								//printf("\tst1, st2, st3\t\t\tSpecify subtriggers 1, 2 and
								//3\n");
								printf("\thv1, hv2, hv3\t\t\tSpecify high voltages ...\n");
								printf("\ttm\t\t\t\tSpecify Time Mode for GPS Receiver (0 - UTC, 1 - GPS)\n");

								printf("\n\tOptions:\n");
								printf("\t-f <filename>\t\t\tSpecify file name\n");
								printf("\t-c <# bytes>\t\t\tNumber of bytes to read/write\n");
								printf("\t-b <byte>\t\t\tValue to load into register\n");

								printf("\n\n");
				}
}

void StrcpyS(char *szDst, size_t cchDst, const char *szSrc) {

#if defined (WIN32)     

				strcpy_s(szDst, cchDst, szSrc);

#else

				if ( 0 < cchDst ) {

								strncpy(szDst, szSrc, cchDst - 1);
								szDst[cchDst - 1] = '\0';
				}

#endif
}      
int parse_param(int argc, char *argv[]) {

				int    arg;

				/* Initialize default flag values */
				fGetReg    = 0;
				fPutReg    = 0;
				fGetRegSet = 0;
				fPutRegSet = 0;
				fToFile    = 0;
				fToStdout  = 0;
				fGetPT     = 0;
				fGetGPS    = 0;
				fFile      = 0;
				fCount     = 0;
				fByte      = 0;
				fData      = 0;

				/* Ensure sufficient paramaters. Need at least program name and
				 ** action flag
				 */
				if (argc < 2) {
								return 0;
				}

				/* The first parameter is the action to perform. Copy the
				 ** first parameter into the action string.
				 */
				StrcpyS(scAction, MAXCHRLEN, argv[1]);
				if(strcmp(scAction, "-r") == 0) {
								fGetReg = 1;
				} else if( strcmp(scAction, "-p") == 0) {
								fPutReg = 1;
				} else if( strcmp(scAction, "-a") == 0) {
								fGetRegSet = 1;
								return 1;
				} else if( strcmp(scAction, "-v") == 0) {
								fshowversion = 1;
								return 0;
				} else if( strcmp(scAction, "-s") == 0) {
								fPutRegSet = 1;
				} else if( strcmp(scAction, "-f") == 0) {
								fToFile = 1;
				} else if( strcmp(scAction, "-o") == 0) {
								fToStdout = 1;
								return 1;
				} else if( strcmp(scAction, "-t") == 0) {
								fGetPT = 1;
								return 1;
				} else if( strcmp(scAction, "-g") == 0) {
								fGetGPS = 1;
								return 1;
				} else { // unrecognized action
								return 0;
				}
				/* Second paramater is target register on device. Copy second
				 ** paramater to the register string */

				if (fPutRegSet) {
								StrcpyS(scReg, MAXCHRLEN, argv[2]);
								/*Registers for Triggers*/
								if(strcmp(scReg, "t1") == 0) {
												scRegister[0] = '1'; /* registers 1 and 2 are for trigger 1*/
								} else if(strcmp(scReg, "t2") == 0) {
												scRegister[0] = '3'; /* registers 3 and 4 are for trigger 2*/
								} else if(strcmp(scReg, "t3") == 0) {
												scRegister[0] = '5'; /* registers 5 and 6 are for trigger 3*/
								}
								/*Registers for Subtrigger*/
								else if(strcmp(scReg, "st1") == 0) {
												scRegister[0] = '7'; /* registers 7 and 8 are for scaler 1*/
								} else if(strcmp(scReg, "st2") == 0) {
												scRegister[0] = '9'; /* registers 9 and 10 are for scaler 2a*/
								} else if(strcmp(scReg, "st3") == 0) {
												scRegister[0] = '1'; /* registers 11 and 12 are for scaler 3a*/
												scRegister[1] = '1';
								}
								/*Registers for High Voltage*/
								else if(strcmp(scReg, "hv1") == 0) {
												scRegister[0] = '1'; /* registers 13 and 14 are for DAC 4 aka hv1*/
												scRegister[1] = '3';
								} else if(strcmp(scReg, "hv2") == 0) {
												scRegister[0] = '1'; /* registers 15 and 16 are for PWM 1*/
												scRegister[1] = '5';
								} else if(strcmp(scReg, "hv3") == 0) {
												scRegister[0] = '1'; /* registers 17 and 18 are for PWM 2*/
												scRegister[1] = '7';
								} else if(strcmp(scReg, "tm") == 0) {
												scRegister[0] = '1'; /* register 19 are for Time Mode*/
												scRegister[1] = '9';
								}
								/*Unrecognized */
								else { // unrecognized register to set
												return 0;
								}
								//scCount[0] = '4';
								//fCount = 1;
								StrcpyS(scData, 16, argv[3]);
								if((strncmp(scReg, "hv",2) == 0)) {
												if (atoi(scData)>4000) {
																printf ("Error: maximum voltage 4000\n");
																exit(1);
												}
								}
								fData = 1;
				} else if(fToFile) {
								if(argv[2] != NULL) {
												StrcpyS(scFile, MAXFILENAMELEN, argv[2]);
												fFile = 1;
								} else {
												return 0;
								}
				} else {
								StrcpyS(scRegister, MAXCHRLEN, argv[2]);

								/* Parse the command line parameters. */
								arg = 3;
								while(arg < argc) {

												/* Check for the -f parameter used to specify the
												 ** input/output file name.
												 */
												if (strcmp(argv[arg], "-f") == 0) {
																arg += 1;
																if (arg >= argc) {
																				return 0;
																}
																StrcpyS(scFile, 16, argv[arg++]);
																fFile = 1;
												}

												/* Check for the -c parameter used to specify the
												 ** number of bytes to read/write from file.
												 */
												else if (strcmp(argv[arg], "-c") == 0) {
																arg += 1;
																if (arg >= argc) {
																				return 0;
																}
																StrcpyS(scCount, 16, argv[arg++]);
																fCount = 1;
												}

												/* Check for the -b paramater used to specify the
												 ** value of a single data byte to be written to the register
												 */
												else if (strcmp(argv[arg], "-b") == 0) {
																arg += 1;
																if (arg >= argc) {
																				return 0;
																}
																StrcpyS(scByte, 16, argv[arg++]);
																fByte = 1;
												}

												/* Not a recognized parameter
												 */
												else {
																return 0;
												}
								} // End while

								/* Input combination validity checks
								 */
								if( fPutReg && !fByte ) {
												printf("Error: No byte value provided\n");
												return 0;
								}
								if( (fToFile ) && !fFile ) {
												printf("Error: No filename provided\n");
												return 0;
								}

								return 1;
				}
				return 1;
}

float get_voltage(unsigned long offset)
{
				int16_t value;
				value = (int16_t) dev_read(xadc_ptr, offset);
				//  printf("The Voltage is: %lf V\n", (value>>4)*XADC_CONV_VAL);
				return ((value>>4)*XADC_CONV_VAL);
}

void set_voltage(unsigned long offset, float value)
{
//fit after calibration. See file data_calib.txt in /ramp_test directory 
// y = a*x + b
//a               = 0.0382061     
//b               = 4.11435   
        int dac_val;
        float a = 0.0382061, b = 4.11435;
        dac_val = (int)(value - b)/a;

				dev_write(cfg_ptr, offset, dac_val);
				  printf("The Voltage is: %.1lf mV\n", value);
				  printf("The DAC value is: %d DACs\n", dac_val);
}

int main(int argc, char *argv[])
{
				int i, p=0,a,b=40000;
				unsigned int val;
				pthread_t t1;
//FIXME: just for test commented
/*				if (!parse_param(argc, argv)) {
								show_usage(argv[0]);
								return 1;
				}
*/

				signal(SIGINT, signal_handler);

				//initialize devices. TODO: add error checking 
				int_init();    
				cfg_init();    
				sts_init();    
				xadc_init();    

      //dev_write(cfg_ptr, CFG_RESET_GRAL_OFFSET, 8); //first reset
      dev_write(cfg_ptr, CFG_RESET_GRAL_OFFSET, RST_PPS_TRG_FIFO_MASK); //first reset
       printf("STATUS Register: 0x%08d\n",dev_read(cfg_ptr, 0));

								while(!interrupted) wait_for_interrupt(int_fd, int_ptr);

//STS test
				//do a loop looking for the position in writer
//				while(!interrupted){
//								printf("POSITION: 0x%08d\n",dev_read(sts_ptr, 0));
//								sleep(1);
//				}  

//XADC test
//			while(!interrupted){
//							printf("Voltage at AI0: %lf V\n",get_voltage(XADC_AI0_OFFSET));
//							printf("Voltage at AI1: %lf V\n",get_voltage(XADC_AI1_OFFSET));
//							printf("Voltage at AI2: %lf V\n",get_voltage(XADC_AI2_OFFSET));
//							printf("Voltage at AI3: %lf V\n",get_voltage(XADC_AI3_OFFSET));
//							printf("\n\n\n");
//							sleep(1);
//			}  
//AO test
      
//      dev_write(cfg_ptr, CFG_RESET_GRAL_OFFSET, 0x8); //first reset
//      set_voltage(CFG_DAC_PWM0_OFFSET, 600);
//      sleep(3);
//
//      dev_write(cfg_ptr, CFG_RESET_GRAL_OFFSET, ~0x8); //first reset
//      for(a=40;a<60;a++)
//{
//							printf("Colocando valor DAC: %d \n",b);
//              dev_write(cfg_ptr, CFG_DAC_PWM0_OFFSET, b);
//              b +=1000;
//              getchar();
//              sleep(1); 
//
//}
				//				printf("\n\n\n");
				//				printf("STS: 0x%08d\n",dev_read(int_ptr, XIL_AXI_INTC_ISR_OFFSET));
				//				printf("IPR: 0x%08d\n",dev_read(int_ptr, XIL_AXI_INTC_IPR_OFFSET));
				//				printf("IER: 0x%08d\n",dev_read(int_ptr, XIL_AXI_INTC_IER_OFFSET));
				//				printf("IAR: 0x%08d\n",dev_read(int_ptr, XIL_AXI_INTC_IAR_OFFSET));
				//				printf("SIE: 0x%08d\n",dev_read(int_ptr, XIL_AXI_INTC_SIE_OFFSET));
				//				printf("CIE: 0x%08d\n",dev_read(int_ptr, XIL_AXI_INTC_CIE_OFFSET));
				//				printf("IVR: 0x%08d\n",dev_read(int_ptr, XIL_AXI_INTC_IVR_OFFSET));
				//				printf("MER: 0x%08d\n",dev_read(int_ptr, XIL_AXI_INTC_MER_OFFSET));
				//				printf("IMR: 0x%08d\n",dev_read(int_ptr, XIL_AXI_INTC_IMR_OFFSET));
				//				printf("ILR: 0x%08d\n",dev_read(int_ptr, XIL_AXI_INTC_ILR_OFFSET));
				//				printf("IVAR: 0x%08d\n",dev_read(int_ptr, XIL_AXI_INTC_IVAR_OFFSET));

				// unmap and close the devices 
				munmap(int_ptr, dev_size);
				munmap(cfg_ptr, dev_size);
				munmap(sts_ptr, dev_size);
				munmap(xadc_ptr, dev_size);
				close(int_fd);
				close(cfg_fd);
				close(sts_fd);
				close(xadc_fd);

				return 0;
}