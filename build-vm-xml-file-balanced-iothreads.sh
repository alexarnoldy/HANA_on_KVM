#!/bin/bash

##### NEED TO TEST FOR XMLLINT AND XMLSTARLET (AKA XML)
## Script to create VM XML file, including vCPU, emulator, IOThread and NUMA node pinnings
RED='\033[0;31m'
LBLUE='\033[1;36m'
NC='\033[0m'
WORKING_DIR=/tmp/$$

mkdir -p $WORKING_DIR

echo -e "    Enter the ${LBLUE}NAME${NC} of the VM:"
read VM_NAME
echo ""
echo ""
echo -e "    Enter the absolute path name to place the output file:"
read PATH_TO_OUTPUT_FILE
FILE_LOCATION=$PATH_TO_OUTPUT_FILE/$VM_NAME.xml
echo ""
echo -e "    ${LBLUE}The final VM XML will be: $FILE_LOCATION${NC}"
echo ""
echo ""

####**** Gather the CPU cores to used 
##echo "The CPU cores on this system are:"
##lscpu | grep ^"NUMA node"." " | awk -F, '{print$1}'
##echo ""

## New method to specify cores on a per NUMA node basis
lscpu | grep ^"NUMA node"." " | awk -F, '{print$1}' | sed 's/A\ /A_/g' | sed 's/CPU(s)//' > $WORKING_DIR/ALL_NUMA_NODES_WITH_CPU_CORES
COUNTER=1
while [  $COUNTER -le $LINES ]
do 
	THIS_LINE=`head  -$COUNTER $WORKING_DIR/ALL_NUMA_NODES_WITH_CPU_CORES | tail -1`
	THIS_NUMA_NODE=`echo $THIS_LINE | awk '{print$1}'`
## BEGIN ## Gather cores for the VM
	echo "These are the CPUs on $THIS_LINE" 
	echo -e "    Enter the ${LBLUE}FIRST${NC} CPU from this NUMA node to be allocated to this VM (Just press Enter to skip this NUMA node):" 
	read START
	if [ -z ${START} ]; then START=0;fi
	echo -e "    Enter the ${LBLUE}LAST${NC} CPU to be allocated to this VM (Just press Enter to skip this NUMA node):"
	read END
	if [ -z ${END} ]; then END=0;fi
## END ## Gather cores for the VM
## BEGIN ## Iterate through the cores to find the hyper-thread siblings
	cat /dev/null > $WORKING_DIR/VM_CPU_CORES_ITERATED_$THIS_NUMA_NODE
	while [ $START -le $END ]; do  echo $START >> $WORKING_DIR/VM_CPU_CORES_ITERATED_$THIS_NUMA_NODE; START=$(($START+1));done
	cat /dev/null > $WORKING_DIR/VM_CPU_CORES_ITERATED_SIBLINGS_$THIS_NUMA_NODE

	for EACH in `cat $WORKING_DIR/VM_CPU_CORES_ITERATED_$THIS_NUMA_NODE`; do cat /sys/devices/system/cpu/cpu$EACH/topology/thread_siblings_list >> $WORKING_DIR/VM_CPU_CORES_ITERATED_SIBLINGS_$THIS_NUMA_NODE; done
	cat $WORKING_DIR/VM_CPU_CORES_ITERATED_SIBLINGS_$THIS_NUMA_NODE | sort -n | uniq > $WORKING_DIR/VM_CPU_CORES_ITERATED_SIBLINGS_UNIQ_$THIS_NUMA_NODE
## END ## Iterate through the cores to find the hyper-thread siblings
## BEGIN ## Establish cores for emulator threads
	echo -e "    How many CPU cores from this NUMA node will be used for ${LBLUE}QEMU Emulator threads${NC} (Just press Enter to skip this NUMA node)?"
	read EMULATOR_COUNT
	if [ -z ${EMULATOR_COUNT} ]; then EMULATOR_COUNT=0;fi
	cat /dev/null > $WORKING_DIR/VM_CPU_CORES_EMULATOR_$THIS_NUMA_NODE
	head -`echo $EMULATOR_COUNT` $WORKING_DIR/VM_CPU_CORES_ITERATED_SIBLINGS_UNIQ_$THIS_NUMA_NODE > $WORKING_DIR/VM_CPU_CORES_EMULATOR_$THIS_NUMA_NODE
	tr '\n' , < $WORKING_DIR/VM_CPU_CORES_EMULATOR_$THIS_NUMA_NODE > $WORKING_DIR/VM_CPU_CORES_EMULATOR.tmp
	mv $WORKING_DIR/VM_CPU_CORES_EMULATOR.tmp $WORKING_DIR/VM_CPU_CORES_EMULATOR_$THIS_NUMA_NODE
## END ## Establish cores for emulator threads
## BEGIN ## Establish cores for iothreads
## Same as emulator but replace EMULATOR with IOTHREAD and change head statement
	echo -e "    How many CPU cores from this NUMA node will be used for ${LBLUE}QEMU  IOThreads${NC} (Just press Enter to skip this NUMA node)?"
	read IOTHREAD_COUNT
	if [ -z ${IOTHREAD_COUNT} ]; then IOTHREAD_COUNT=0;fi
	cat /dev/null > $WORKING_DIR/VM_CPU_CORES_IOTHREADS_$THIS_NUMA_NODE
	head -`echo $(( $EMULATOR_COUNT + $IOTHREAD_COUNT ))` $WORKING_DIR/VM_CPU_CORES_ITERATED_SIBLINGS_UNIQ_$THIS_NUMA_NODE | tail -`echo $IOTHREAD_COUNT` > $WORKING_DIR/VM_CPU_CORES_IOTHREADS_$THIS_NUMA_NODE
	tr '\n' , < $WORKING_DIR/VM_CPU_CORES_IOTHREADS_$THIS_NUMA_NODE > $WORKING_DIR/VM_CPU_CORES_IOTHREADS.tmp
	mv $WORKING_DIR/VM_CPU_CORES_IOTHREADS.tmp $WORKING_DIR/VM_CPU_CORES_IOTHREADS_$THIS_NUMA_NODE
## END ## Establish cores for iothreads
## BEGIN ## Establish reamining cores for the VM
	tail -n +`echo $(( $EMULATOR_COUNT + $IOTHREAD_COUNT + 1 ))` $WORKING_DIR/VM_CPU_CORES_ITERATED_SIBLINGS_UNIQ_$THIS_NUMA_NODE > $WORKING_DIR/VM_CPU_CORES_REMAINING_$THIS_NUMA_NODE
	tr , '\n' < $WORKING_DIR/VM_CPU_CORES_REMAINING_$THIS_NUMA_NODE > $WORKING_DIR/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS_$THIS_NUMA_NODE
	TOTAL_VCPUS=`wc -l $WORKING_DIR/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS_$THIS_NUMA_NODE | awk '{print$1}'`
	VM_CPU_REMAINING_COMMA_SEPARATED=`tr '\n' , < $WORKING_DIR/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS_$THIS_NUMA_NODE`
## END ## Establish reamining cores for the VM
	let COUNTER=COUNTER+1
	LINES=`wc -l $WORKING_DIR/ALL_NUMA_NODES_WITH_CPU_CORES | awk '{print$1}'`
done

## Consolidate cores from each NUMA node into single list of cores to be used for QEMU emulator threads
cat $WORKING_DIR/VM_CPU_CORES_EMULATOR_* > $WORKING_DIR/VM_CPU_CORES_EMULATOR
VM_CPU_CORES_EMULATOR=`cat $WORKING_DIR/VM_CPU_CORES_EMULATOR`
echo "${VM_CPU_CORES_EMULATOR::-1}" > $WORKING_DIR/VM_CPU_CORES_EMULATOR.tmp
mv $WORKING_DIR/VM_CPU_CORES_EMULATOR.tmp $WORKING_DIR/VM_CPU_CORES_EMULATOR

## Consolidate cores from each NUMA node into single list of cores to be used for QEMU IOThreads
cat $WORKING_DIR/VM_CPU_CORES_IOTHREADS_* > $WORKING_DIR/VM_CPU_CORES_IOTHREADS
VM_CPU_CORES_IOTHREADS=`cat $WORKING_DIR/VM_CPU_CORES_IOTHREADS`
echo "${VM_CPU_CORES_IOTHREADS::-1}" > $WORKING_DIR/VM_CPU_CORES_IOTHREADS.tmp
mv $WORKING_DIR/VM_CPU_CORES_IOTHREADS.tmp $WORKING_DIR/VM_CPU_CORES_IOTHREADS


## Consolidate cores from each NUMA node into single list of cores to be used for vCPUs
cat $WORKING_DIR/VM_CPU_CORES_IOTHREADS_* > $WORKING_DIR/VM_CPU_CORES_IOTHREADS
VM_CPU_CORES_IOTHREADS=`cat $WORKING_DIR/VM_CPU_CORES_IOTHREADS`
echo "${VM_CPU_CORES_IOTHREADS::-1}" > $WORKING_DIR/VM_CPU_CORES_IOTHREADS.tmp
mv $WORKING_DIR/VM_CPU_CORES_IOTHREADS.tmp $WORKING_DIR/VM_CPU_CORES_IOTHREADS
#echo "${VM_CPU_REMAINING_COMMA_SEPARATED::-1}" > /tmp/VM_CPU_REMAINING_COMMA_SEPARATED





################## Uncomment after testing ################
exit
################## Uncomment after testing ################

##echo -e "    Enter the ${LBLUE}FIRST${NC} CPU to be allocated to this VM:"
############## read START
################## Uncomment after testing ################
##echo -e "    Enter the ${LBLUE}LAST${NC} CPU to be allocated to this VM:"
################## Uncomment after testing ################
############## read END
################## Uncomment after testing ################

echo -e "    Enter the amount of ${LBLUE}MEMORY${NC} in MiB to be alloacted to this VM:"
################## Uncomment after testing ################
read MEMORY
################## Uncomment after testing ################



## Iterate through the cores to find the hyper-thread siblings

## cat /dev/null > /tmp/VM_CPU_CORES_ITERATED
## while [ $START -le $END ]; do  echo $START >> /tmp/VM_CPU_CORES_ITERATED; START=$(($START+1));done

##cat /dev/null > /tmp/VM_CPU_CORES_ITERATED_SIBLINGS
##for EACH in `cat /tmp/VM_CPU_CORES_ITERATED`; do cat /sys/devices/system/cpu/cpu$EACH/topology/thread_siblings_list >> /tmp/VM_CPU_CORES_ITERATED_SIBLINGS; done

##cat /tmp/VM_CPU_CORES_ITERATED_SIBLINGS | sort -n | uniq > /tmp/VM_CPU_CORES_ITERATED_SIBLINGS_UNIQ



##echo -e "    How many CPU cores will be used for ${LBLUE}QEMU Emulator threads${NC}?"

################## Uncomment after testing ################
############## read EMULATOR_COUNT
################## Uncomment after testing ################


##echo ""

#echo -e "    How many CPU cores will be used for ${LBLUE}QEMU IOThreads${NC}?"

################## Uncomment after testing ################
############## read IOTHREAD_COUNT
################## Uncomment after testing ################
################## Remove after testing ################
##VM_NAME=test
##FILE_LOCATION=/tmp/test.xml
##START=1
##END=16
##MEMORY=2
##IOTHREAD_COUNT=2
##EMULATOR_COUNT=2
################## Remove after testing ################


## Establish list of logical CPUs for emulator threads from the beginning of the list of logical CPUs allocated to the VM
#tr , '\n' < /tmp/VM_CPU_CORES_EMULATOR > /tmp/VM_CPU_CORES_EMULATOR_SORTED_BY_SIBLINGS

## Process the list of emulator threads, removing the trailing comma
#VM_CPU_CORES_EMULATOR=`tr '\n' , < /tmp/VM_CPU_CORES_EMULATOR `
#echo "${VM_CPU_CORES_EMULATOR::-1}" > /tmp/VM_CPU_CORES_EMULATOR.tmp
#mv /tmp/VM_CPU_CORES_EMULATOR.tmp /tmp/VM_CPU_CORES_EMULATOR

#echo ""
#cat /tmp/VM_CPU_CORES_EMULATOR_SORTED_BY_SIBLINGS
#echo ""

## Establish list of logical CPUs for iothreads
#head -`echo $(( $EMULATOR_COUNT + $IOTHREAD_COUNT ))` /tmp/VM_CPU_CORES_ITERATED_SIBLINGS_UNIQ | tail -`echo $IOTHREAD_COUNT` > /tmp/VM_CPU_CORES_IOTHREADS
#tr , '\n' < /tmp/VM_CPU_CORES_IOTHREADS > /tmp/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS

#echo ""
#cat /tmp/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS
#echo ""

## Establish the remaining logical CPUs for the VM
#tail -n +`echo $(( $EMULATOR_COUNT + $IOTHREAD_COUNT + 1 ))` /tmp/VM_CPU_CORES_ITERATED_SIBLINGS_UNIQ > /tmp/VM_CPU_CORES_REMAINING
#tr , '\n' < /tmp/VM_CPU_CORES_REMAINING > /tmp/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS
#TOTAL_VCPUS=`wc -l /tmp/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS | awk '{print$1}'`

## Process the list of remaining CPUs, removing the trailing comma
#VM_CPU_REMAINING_COMMA_SEPARATED=`tr '\n' , < /tmp/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS`
#echo "${VM_CPU_REMAINING_COMMA_SEPARATED::-1}" > /tmp/VM_CPU_REMAINING_COMMA_SEPARATED



####
## Beginning of creating the XML file
####
virt-install --name $VM_NAME --memory $MEMORY --vcpu $TOTAL_VCPUS --disk none --pxe --print-xml 2 --dry-run > $FILE_LOCATION

#### Begin xml (xmlstarlet) updates to the base file created by virt-install
#### Use xml el -v <file> to see all fo the elements, attributes, and values #### 
#### Later will replace as many xmlstarlet commands with virt-xml commands as possible

## Add cputune, numatune and memoryBacking (plus hugepages) elements to the XML file
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
xml ed --subnode "/domain" --type elem -n "cputune" -v "" $FILE_LOCATION > $FILE_LOCATION.tmp 
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
xml ed --subnode "/domain" --type elem -n "numatune" -v "" $FILE_LOCATION > $FILE_LOCATION.tmp 
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
xml ed --subnode "/domain" --type elem -n "memoryBacking" -v "" $FILE_LOCATION > $FILE_LOCATION.tmp 
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
xml ed --subnode "/domain/memoryBacking" --type elem -n "hugepages" -v "" $FILE_LOCATION > $FILE_LOCATION.tmp 
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
xml ed --subnode "/domain/memoryBacking" --type elem -n "nosharepages" -v "" $FILE_LOCATION > $FILE_LOCATION.tmp 

## Configure hugepages as 1GiB
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
xml ed --subnode "/domain/memoryBacking/hugepages" --type elem -n "page size='1048576' unit='KiB'" -v "" $FILE_LOCATION > $FILE_LOCATION.tmp 

## Add vCPU pinning list to the XML file
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
COUNTER=1 
LINES=`wc -l /tmp/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS | awk '{print$1}'` 
while [  $COUNTER -le $LINES ] 
do 
	THIS_LINE=`head  -$COUNTER /tmp/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS | tail -1`
	xml ed --subnode "/domain/cputune" --type elem -n "vcpupin vcpu='`echo $(( $COUNTER - 1 ))`' cpuset='$THIS_LINE'" $FILE_LOCATION > $FILE_LOCATION.tmp
	mv $FILE_LOCATION.tmp $FILE_LOCATION
	let COUNTER=COUNTER+1
	LINES=`wc -l /tmp/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS | awk '{print$1}'`
done

## Add NUMA node pinning to the XML file
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
numactl --hardware | grep cpus | sed 's/node /node/' > /tmp/NUMA_NODES_TO_CPUS
cat /dev/null > /tmp/ALL_NUMA_NODES
for EACH in `cat /tmp/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS`
do 
	grep -w $EACH /tmp/NUMA_NODES_TO_CPUS | awk -Fe '{print$2}' | awk '{print$1}' >> /tmp/ALL_NUMA_NODES
done
sort /tmp/ALL_NUMA_NODES | uniq > /tmp/ALL_NUMA_NODES_UNIQ

## Process the list of NUMA nodes, removing the trailing comma
ALL_NUMA_NODES_UNIQ=`tr '\n' , < /tmp/ALL_NUMA_NODES_UNIQ`
echo "${ALL_NUMA_NODES_UNIQ::-1}" > /tmp/ALL_NUMA_NODES_COMMA_SEPARATED
## Set up the memory mode for all NUMA nodes
xml ed --subnode "/domain/numatune" --type elem -n "memory mode='strict' nodeset='`cat /tmp/ALL_NUMA_NODES_COMMA_SEPARATED`'" $FILE_LOCATION > $FILE_LOCATION.tmp

## Add NUMA node pinning to the XML file
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
COUNTER=1 
LINES=`wc -l /tmp/ALL_NUMA_NODES_UNIQ | awk '{print$1}'` 
while [  $COUNTER -le $LINES ] 
do 
	THIS_LINE=`head  -$COUNTER /tmp/ALL_NUMA_NODES_UNIQ | tail -1`
	xml ed --subnode "/domain/numatune" --type elem -n "memnode cellid='`echo $(( $COUNTER - 1 ))`' mode='strict' nodeset='$THIS_LINE'" $FILE_LOCATION > $FILE_LOCATION.tmp
	mv $FILE_LOCATION.tmp $FILE_LOCATION
	let COUNTER=COUNTER+1
	LINES=`wc -l /tmp/ALL_NUMA_NODES_UNIQ | awk '{print$1}'`
done




## Update hpet timer
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
xml ed -u "domain/clock/timer[@name='hpet' and @present='no']"/@present -v yes $FILE_LOCATION > $FILE_LOCATION.tmp

## Add emulatorpinning to the XML file
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
xml ed --subnode "/domain/cputune" --type elem -n "emulatorpin cpuset='`cat /tmp/VM_CPU_CORES_EMULATOR`'" -v "" $FILE_LOCATION > $FILE_LOCATION.tmp

## Add total number of iothreads to the XML file
## virt-install and virt-xml don't seem to support iothreads
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
xml ed --subnode "/domain" --type elem -n "iothreads" -v "`wc -l /tmp/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS | awk '{print$1}'`" $FILE_LOCATION > $FILE_LOCATION.tmp

## Add iothreadpinning list to the XML file
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
COUNTER=1 
LINES=`wc -l /tmp/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS | awk '{print$1}'` 
while [  $COUNTER -le $LINES ] 
do 
	THIS_LINE=`head  -$COUNTER /tmp/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS | tail -1`
	xml ed --subnode "/domain/cputune" --type elem -n "iothreadpin iothread='`echo $COUNTER`' cpuset='$THIS_LINE'" $FILE_LOCATION > $FILE_LOCATION.tmp
	mv $FILE_LOCATION.tmp $FILE_LOCATION
	let COUNTER=COUNTER+1
	LINES=`wc -l /tmp/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS | awk '{print$1}'`
done

#### Begin virt-xml updates to the XML file

## vcpu placement
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
virt-xml --edit  --vcpu placement="static" < $FILE_LOCATION > $FILE_LOCATION.tmp
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
virt-xml --edit  --vcpu cpuset="`cat /tmp/VM_CPU_REMAINING_COMMA_SEPARATED`" < $FILE_LOCATION > $FILE_LOCATION.tmp
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
virt-xml --edit --vcpu=`wc -l /tmp/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS | awk '{print$1}'` < $FILE_LOCATION > $FILE_LOCATION.tmp

## iothreads
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
#virt-xml --add-device iothreads=`wc -l /tmp/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS | awk '{print$1}'` < $FILE_LOCATION > $FILE_LOCATION.tmp
#virt-xml --edit --iothreads=`wc -l /tmp/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS | awk '{print$1}'` < $FILE_LOCATION > $FILE_LOCATION.tmp



mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
cat $FILE_LOCATION
rm /tmp/VM_CPU_CORES_ITERATED
rm /tmp/VM_CPU_CORES_ITERATED_SIBLINGS 
#rm /tmp/VM_CPU_CORES_ITERATED_SIBLINGS_UNIQ
rm /tmp/VM_CPU_CORES_EMULATOR
###rm /tmp/VM_CPU_CORES_EMULATOR_SORTED_BY_SIBLINGS
rm /tmp/VM_CPU_CORES_IOTHREADS
#rm /tmp/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS
#rm /tmp/VM_CPU_CORES_REMAINING
#rm /tmp/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS

####### virt-install --name test --memory 4096 --vcpu 2 --disk none --pxe --print-xml --dry-run --cputune vcpupin0.vcpu=0,vcpupin0.cpuset=2,vcpupin1.vcpu=1,vcpupin1.cpuset=8
