#!/bin/bash
####### cpu_mask_calculator.sh
## Simple shell script to create a bit mask based on a set number of positions and bits to 
##  turn on (from the right).                                           
## Primary intention is to create a CPU bit mask for pinning DPDK threads to both hyper-threads
##  of specific CPU cores.                                                               
## DOES NOT NEED TO BE RUN ON THE TARGET SYSTEM, but does require the rev and bc commands.
## Alex Arnoldy (alex.arnoldy@suse.com); 10/01/2019 31/12/2018, 26/12/2018, 12/12/2018 

    

## Test to see if the bc and rev commands are available
command -v bc >/dev/null 2>&1 || { echo >&2 \
        "Could not find the bc command.  Aborting."; exit 1; }
command -v rev >/dev/null 2>&1 || { echo >&2 \
        "Could not find the rev command.  Aborting."; exit 1; }
 
## TOTAL_LCPUS= is the number of logical CPUs on the system. 
echo "Enter the total number of logical CPUs on the system 
This can be found with the command: ls -d /sys/devices/system/cpu/cpu[0-9]* | wc -l:"
read TOTAL_LCPUS

HIGHEST_LCPU=`echo $(($TOTAL_LCPUS - 1))`

## LCPUS_TO_BE_MASKED="" is a double-quoted, space separated list of logical CPUs 
##  to be included in the mask. 
## For best results, these should include the two hyper-thread 
##  siblings for a physical CPU core. 
## To find the sibling core for logical CPU<n>:  
##  cat /sys/devices/system/cpu/cpu<n>/topology/thread_siblings_list
## Remember that 20 logical CPUs will be numbered from 0 through 19. 
echo "Enter a space separated list of the logical CPUs to be included 
in the mask (Allowed values are 0 through $HIGHEST_LCPU):"
read LCPUS_TO_BE_MASKED
   

## Create the mask with a zero for each logical CPU
cat /dev/null > /tmp/cpu_mask.bin
COUNTER=0
while [  $COUNTER -lt $TOTAL_LCPUS ]     
        do printf 0 >> /tmp/cpu_mask.bin
        let COUNTER=COUNTER+1      
done                               
                                                    
## Replace the appropriate zero with a one for the logical CPUs to be masked
## Note: This builds the mask left-to-right. The rev command will be needed to flip
##  it to right-to-left orientation.
for EACH in `echo $LCPUS_TO_BE_MASKED`
do                                             
        if (( $EACH > $HIGHEST_LCPU )) 
          then echo "$EACH is out of range for a system with a total of $TOTAL_LCPUS LCPUs. 
Allowed values are 0 through $HIGHEST_LCPU. Aborting" 
                  exit 1
        fi
        sed -E "s/^(.{$EACH})0/\11/" /tmp/cpu_mask.bin > /tmp/cpu_mask.tmp
        mv /tmp/cpu_mask.tmp /tmp/cpu_mask.bin
done                  
                      
## Flip the binary mask to right-to-left orientation
rev /tmp/cpu_mask.bin > /tmp/cpu_mask.tmp
mv /tmp/cpu_mask.tmp /tmp/cpu_mask.bin

BINARY_MASK=`cat /tmp/cpu_mask.bin`
HEX_MASK=`echo "obase=16;ibase=2;$BINARY_MASK" | bc` 
              
echo "binary mask is:" $BINARY_MASK
echo "hex mask is: 0x"$HEX_MASK     

