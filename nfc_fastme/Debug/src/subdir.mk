################################################################################
# Automatically-generated file. Do not edit!
################################################################################

# Add inputs and outputs from these tool invocations to the build variables 
LD_SRCS += \
../src/lscript.ld 

C_SRCS += \
../src/app_cli.c \
../src/ftl_core.c \
../src/ftl_mon.c \
../src/main.c \
../src/merge_smoke_test.c \
../src/nfc.c \
../src/nfc_reg.c \
../src/platform.c 

OBJS += \
./src/app_cli.o \
./src/ftl_core.o \
./src/ftl_mon.o \
./src/main.o \
./src/merge_smoke_test.o \
./src/nfc.o \
./src/nfc_reg.o \
./src/platform.o 

C_DEPS += \
./src/app_cli.d \
./src/ftl_core.d \
./src/ftl_mon.d \
./src/main.d \
./src/merge_smoke_test.d \
./src/nfc.d \
./src/nfc_reg.d \
./src/platform.d 


# Each subdirectory must supply rules for building sources it contributes
src/%.o: ../src/%.c
	@echo 'Building file: $<'
	@echo 'Invoking: MicroBlaze gcc compiler'
	mb-gcc -Wall -O0 -g3 -c -fmessage-length=0 -MT"$@" -IC:/Users/hp/Desktop/NFC_test/nfc_vitis3/nfc_test_wrapper/export/nfc_test_wrapper/sw/nfc_test_wrapper/standalone_domain/bspinclude/include -mlittle-endian -mcpu=v11.0 -mxl-soft-mul -Wl,--no-relax -ffunction-sections -fdata-sections -MMD -MP -MF"$(@:%.o=%.d)" -MT"$(@)" -o "$@" "$<"
	@echo 'Finished building: $<'
	@echo ' '


